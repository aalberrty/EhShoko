#if DEBUG || HARNESS
import CoreML
import EhCore
import EhModels
import EhPageTranslation
import Foundation

/// The runs that use the models without the service: each model loaded alone, and the
/// translator over a file of lines.
extension TranslationHarnessRun {
    // MARK: Loads

    /// Every Core ML model of the run's choices loaded once, one after the other, and let go:
    /// each function of a model that has several (the translator's encoder: `L32`, `L64`,
    /// `L128`) on its own. In a fresh process this is what a first press after a launch pays
    /// for each model; right after an install it is the first load.
    func runLoads() async throws {
        let store = try await waitForStore()
        let entries = await MainActor.run { [neededArtifacts, options] in
            neededArtifacts.compactMap { id -> (ModelArtifactID, InstalledModelFiles, MLComputeUnits)? in
                guard let files = store.installedFiles(of: id) else { return nil }
                return (id, files, Self.units(of: files.artifact, options: options))
            }
        }
        for (id, files, units) in entries {
            for package in files.artifact.packages {
                let url = files.compiledModel(ofPackage: package)
                let name = "\(id.rawValue)/\(URL(filePath: package).deletingPathExtension().lastPathComponent)"
                for function in await Self.functionNames(of: url) {
                    let label = function.map { "\(name).\($0)" } ?? name
                    await say("loading \(label)")
                    let start = clock.now
                    var load = TranslationHarnessResult.Load(what: label, atS: secondsSinceStart, ms: 0, units: units.harnessName)
                    do {
                        try await Self.loadOnce(url, units: units, function: function)
                    } catch {
                        load.failed = String(describing: error)
                    }
                    load.ms = TranslationHarnessCalls.milliseconds(clock.now - start)
                    result.loads.append(load)
                    await write()
                }
            }
        }
    }

    nonisolated static func units(of artifact: ModelArtifact, options: TranslationHarnessOptions) -> MLComputeUnits {
        let asked: MLComputeUnits? = switch artifact.role {
        case .detector: options.detectorUnits
        case .reader: options.readerUnits
        case .translator: options.translatorUnits
        case .repaint: options.repaintUnits
        }
        if let asked { return asked }
        guard case let .coreML(units) = artifact.loading else { return .cpuAndNeuralEngine }
        return switch units {
        case .cpuOnly: .cpuOnly
        case .cpuAndGPU: .cpuAndGPU
        case .cpuAndNeuralEngine: .cpuAndNeuralEngine
        case .all: .all
        }
    }

    /// `[nil]` for a model with one function.
    @concurrent
    nonisolated static func functionNames(of url: URL) async -> [String?] {
        guard let asset = try? MLModelAsset(url: url), let names = try? await asset.functionNames, names.count > 1 else {
            return [nil]
        }
        return names.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    @concurrent
    nonisolated static func loadOnce(_ url: URL, units: MLComputeUnits, function: String?) async throws {
        let configuration = MLModelConfiguration()
        configuration.computeUnits = units
        if let function { configuration.functionName = function }
        _ = try await MLModel.load(contentsOf: url, configuration: configuration)
    }

    // MARK: Lines

    /// What `-TranslationHarnessLines` holds: the translator's reference files have this shape,
    /// so the Mac's answers and the phone's compare line by line.
    nonisolated struct LinesFile: Decodable {
        struct Page: Decodable {
            var page: String
            var lines: [Line]
        }

        struct Line: Decodable {
            var ja: String
        }

        var pages: [Page]
    }

    /// The translator alone, each page's lines in one call as the pipeline makes it.
    func runLines() async throws {
        let store = try await waitForStore()
        let options = options
        let setup = try await MainActor.run { try TranslationHarnessEnvironment.setup(options, store: store) }
        result.setup = Self.record(of: setup, options: options)
        guard let pipeline = setup.pipeline else { throw TranslationHarnessError("no translator") }
        let fileURL = TranslationHarnessOptions.containerURL(options.linesFile)
        let file = try await Self.readLines(fileURL)

        await say("loading the translator")
        let loadStart = clock.now
        let loader = PageTranslatorLoader(
            languageModel: TranslationHarnessLanguageModel.loader(options),
            computeUnits: pipeline.translatorUnits ?? .cpuAndNeuralEngine
        )
        let translator = try await loader.load(setup.modelSet.translator, from: pipeline.translator)
        var lines = TranslationHarnessResult.Lines(
            file: options.linesFile, loadMs: TranslationHarnessCalls.milliseconds(clock.now - loadStart), pages: []
        )
        for (number, page) in file.pages.enumerated() {
            guard !isPastDeadline else {
                result.stoppedBecause = "time limit after \(number) pages of lines"
                break
            }
            await say("lines of page \(number + 1) of \(file.pages.count)")
            let source = page.lines.map(\.ja)
            let start = clock.now
            let translated = try await translator.translate(source)
            lines.pages.append(
                TranslationHarnessResult.Lines.Page(
                    page: page.page, ms: TranslationHarnessCalls.milliseconds(clock.now - start),
                    lines: zip(source, translated).map { TranslationHarnessResult.Lines.Line(ja: $0, zh: $1) }
                )
            )
            result.lines = lines
            await write()
        }
        result.lines = lines
    }

    @concurrent
    nonisolated static func readLines(_ url: URL) async throws -> LinesFile {
        try JSONDecoder().decode(LinesFile.self, from: Data(contentsOf: url))
    }
}
#endif
