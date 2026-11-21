#if DEBUG || HARNESS
import CoreML
import EhCore
import EhDatabase
import EhModels
import EhPageTranslation
import Foundation
import Synchronization

/// The service the harness drives: the app's own `PageTranslationService` with the real
/// stages and models, built from the harness's choices instead of Settings', and with a
/// cache of its own so nothing the harness translates mixes with the app's.
///
/// The one difference from the app's environment is where the choices come from and that
/// each model the service loads is wrapped to be counted (`TranslationHarnessCalls`).
nonisolated enum TranslationHarnessEnvironment {
    /// The harness's gallery. Its rows and patch files are in the harness's cache only.
    static let gid = "translation-harness"

    static func make(
        setup: PageTranslationSetup, options: TranslationHarnessOptions, calls: TranslationHarnessCalls,
        loads: TranslationHarnessLoads, cache: TranslationHarnessCache
    ) -> PageTranslationEnvironment {
        let languageModel = TranslationHarnessLanguageModel.loader(options)
        return PageTranslationEnvironment(
            setup: { setup },
            imageData: { url in try await readFile(url) },
            loadPipeline: { configuration in
                // The fonts' first use is paid while the models load, as in the app.
                Task.detached(priority: .utility) { _ = FontLibrary.bundled }
                let start = ContinuousClock.now
                do {
                    let pipeline = try await PagePipeline.load(configuration, languageModel: languageModel)
                    loads.add(pipeline: pipeline.loadTimings, ms: TranslationHarnessCalls.milliseconds(.now - start))
                    return pipeline.timed(by: calls)
                } catch {
                    loads.add(failed: "pipeline", error: error, ms: TranslationHarnessCalls.milliseconds(.now - start))
                    throw error
                }
            },
            loadInpainter: { url, units in
                let start = ContinuousClock.now
                do {
                    let model = try await LamaInpainter(compiledModel: url, computeUnits: units)
                    loads.add(what: "repaint", ms: TranslationHarnessCalls.milliseconds(.now - start), units: units)
                    return TimedInpainter(inner: model, calls: calls)
                } catch {
                    loads.add(failed: "repaint", error: error, ms: TranslationHarnessCalls.milliseconds(.now - start))
                    throw error
                }
            },
            writer: cache.writer,
            patchStore: cache.patchStore,
            logger: .liveValue
        )
    }

    @concurrent
    static func readFile(_ url: URL) async throws -> Data {
        try Data(contentsOf: url, options: .mappedIfSafe)
    }

    // MARK: The setup

    enum SetupError: Error, CustomStringConvertible {
        case notInstalled([ModelArtifactID])

        var description: String {
            switch self {
            case let .notInstalled(ids): "not installed: \(ids.map(\.rawValue).joined(separator: ", "))"
            }
        }
    }

    /// The harness's choices over the store's installed files, with the compute units asked
    /// for. A language model's file in the container stands in for the store's install of the
    /// translator; the detector and reader still come from the store.
    @MainActor
    static func setup(_ options: TranslationHarnessOptions, store: PageTranslationModelStore) throws -> PageTranslationSetup {
        var resolvedSet = options.modelSet
        let file = options.modelFile.map(TranslationHarnessOptions.containerURL)
        // The translator's own install is not needed when a file stands in for it; the
        // default translator's is, only so `resolve` gives the detector's and reader's files.
        if file != nil { resolvedSet.translator = .jmtFast1 }
        var setup = PageTranslationSetup.resolve(modelSet: resolvedSet, repaint: options.repaint) {
            store.installedFiles(of: $0)
        }
        guard var pipeline = setup.pipeline else {
            let missing = resolvedSet.artifacts.filter { store.installedFiles(of: $0) == nil }
            throw SetupError.notInstalled(missing)
        }
        if let artifact = options.repaint.artifact, setup.repaint == .off {
            throw SetupError.notInstalled([artifact])
        }
        if let file {
            pipeline.modelSet = options.modelSet
            pipeline.translator = file
            setup.modelSet = options.modelSet
        }
        if let units = options.detectorUnits { pipeline.detectorUnits = units }
        if let units = options.readerUnits { pipeline.readerUnits = units }
        if let units = options.translatorUnits { pipeline.translatorUnits = units }
        if let units = options.repaintUnits { setup.repaintUnits = units }
        setup.pipeline = pipeline
        return setup
    }
}

/// The models a run loaded and how long each took.
nonisolated final class TranslationHarnessLoads: Sendable {
    private let start: ContinuousClock.Instant
    private let records = Mutex<[TranslationHarnessResult.Load]>([])

    init(start: ContinuousClock.Instant) {
        self.start = start
    }

    var all: [TranslationHarnessResult.Load] { records.withLock { $0 } }

    func add(pipeline timings: PipelineLoadTimings, ms: Double) {
        let ms2 = TranslationHarnessCalls.milliseconds
        append(
            TranslationHarnessResult.Load(
                what: "pipeline", atS: secondsSinceStart, ms: ms,
                parts: ["detector": ms2(timings.detector), "reader": ms2(timings.reader), "translator": ms2(timings.translator)]
            )
        )
    }

    func add(what: String, ms: Double, units: MLComputeUnits?) {
        append(TranslationHarnessResult.Load(what: what, atS: secondsSinceStart, ms: ms, units: units?.harnessName))
    }

    func add(failed what: String, error: any Error, ms: Double) {
        append(TranslationHarnessResult.Load(what: what, atS: secondsSinceStart, ms: ms, failed: String(describing: error)))
    }

    private var secondsSinceStart: Double { TranslationHarnessCalls.milliseconds(.now - start) / 1_000 }

    private func append(_ load: TranslationHarnessResult.Load) {
        records.withLock { $0.append(load) }
    }
}

/// The harness's own database and patch folder, in `Library/Caches/TranslationHarness`.
/// Emptied at the start of a run unless the run measures stored pages.
nonisolated struct TranslationHarnessCache: Sendable {
    static let folder = URL.cachesDirectory.appending(path: "TranslationHarness", directoryHint: .isDirectory)
    static var databaseURL: URL { folder.appending(path: "cache.sqlite") }
    static var patchesURL: URL { folder.appending(path: "Patches", directoryHint: .isDirectory) }

    let writer: PageTranslationResultWriter
    let patchStore: PageTranslationPatchStore

    @concurrent
    static func open(keeping: Bool, droppingPatches: Bool) async throws -> TranslationHarnessCache {
        let files = FileManager.default
        if !keeping { try? files.removeItem(at: folder) }
        if droppingPatches { try? files.removeItem(at: patchesURL) }
        let database = try await AppDatabase.open(at: databaseURL)
        return TranslationHarnessCache(
            writer: PageTranslationResultWriter(database: database, logger: .liveValue),
            patchStore: PageTranslationPatchStore(directory: patchesURL)
        )
    }

    @concurrent
    static func remove() async {
        try? FileManager.default.removeItem(at: folder)
    }
}
#endif
