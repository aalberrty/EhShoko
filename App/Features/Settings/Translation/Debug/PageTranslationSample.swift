#if DEBUG
import Dependencies
import EhCore
import EhFeatures
import EhModels
import Foundation

/// Settings › Translation on a store of its own, for screenshots and the scroll check: launch
/// a debug build with `-PageTranslationSample <state>` (and `-PageTranslationSampleToken <text>`
/// for a kept token).
///
/// The sample's catalog is the app's plus the four language models MT24 will list, so the
/// Translate screen has five cards. Its folder is a temporary one, written afresh at each
/// launch with records of installed models (their sizes are the catalog's, their files are
/// empty), so nothing is downloaded or compiled. Its transport never reaches the network:
/// it serves zeros slowly, so a download shows its progress and ends with a checksum that
/// does not match. The settings are the app's own.
///
/// | State | Installed |
/// |---|---|
/// | `ready` | The default set, ogkalu v4-s and Hy-MT2 |
/// | `partial` | The default set without its detector |
/// | `empty` | Nothing |
/// | `preparing` | The default set, each model loading once for 20 s |
/// | `paused` | The default set without its detector, whose download is paused a third of the way |
/// | `downloading` | The same, the detector's download going on from a third of the way |
/// | `offline` | The same with no network: the download waits for a connection |
/// | `noSpace` | The same on a full disk: the download stops at once for want of room |
/// | `failed` | The same with sources that answer 404: the download stops at once |
/// | `noSource` | Nothing, and no private source whatever the settings say: no detector can be had. The store and the Translation screen read settings of the sample's own, a copy of the app's with the address blank, so both show no source and an address typed there is the sample's |
/// | `publicStore` | Nothing, no private source as in `noSource`, and the public store: what someone who builds the app sees first |
///
/// Only `publicStore` has the public store; the other states have none, so each shows what it
/// did before the store existed. The states that download need a private source for the
/// detector, which is private-only: launch them with
/// `-settings.pageTranslationSourceAddress https://models.example` unless the settings hold one.
enum PageTranslationSample: String {
    case ready, partial, empty, preparing, paused
    case downloading, offline, noSpace, failed, noSource, publicStore

    static let atLaunch = UserDefaults.standard.string(forKey: "PageTranslationSample").flatMap(Self.init)

    private static let root = URL.temporaryDirectory.appending(path: "PageTranslationSample", directoryHint: .isDirectory)
    private static var isPrepared = false

    /// The one sample store of the process, which the reader's download sheet shows too.
    static var sampleStore: PageTranslationModelStore? { store }

    private static let store: PageTranslationModelStore? = atLaunch.map { state in
        let choices = ModelStoreChoices.settings(settings)
        let isOffline = state == .offline
        let environment = ModelStoreEnvironment(
            catalog: catalog,
            layout: ModelStoreLayout(root: root),
            transport: SampleTransport(refuses: state == .failed),
            compiler: ModelCompiler(
                compile: { $0 },
                prepare: { _, _ in try await Task.sleep(for: .seconds(atLaunch == .preparing ? 20 : 0)) }
            ),
            // `-PageTranslationSampleToken <text>` starts with a token kept.
            tokens: .inMemory(UserDefaults.standard.string(forKey: "PageTranslationSampleToken")),
            publicStore: state == .publicStore ? ModelCatalog.publicStoreAddress : nil,
            // Less than any download needs (`spaceNeeded` adds 200 MB to what is left).
            freeSpace: { _ in state == .noSpace ? 150_000_000 : 64_000_000_000 },
            connectivity: { AsyncStream { $0.yield(!isOffline) } }
        )
        return PageTranslationModelStore(environment: environment, choices: choices)
    }

    /// The Translation screen's model over the sample store, or `nil` without the argument.
    static func makeModel() -> PageTranslationSettingsModel? {
        guard let store else { return nil }
        return withDependencies {
            $0.pageTranslationModelStore = store
            $0.settings = settings
        } operation: {
            PageTranslationSettingsModel()
        }
    }

    /// The settings the sample's store and Translation screen read: the app's, or for
    /// `noSource` and `publicStore` a copy of them with the address blank, kept apart from the
    /// app's so the sample does not wipe an address the app holds.
    private static let settings: SettingsStore = {
        @Dependency(\.settings) var appSettings
        let suite = "PageTranslationSample"
        guard atLaunch == .noSource || atLaunch == .publicStore, let defaults = UserDefaults(suiteName: suite) else { return appSettings }
        defaults.removePersistentDomain(forName: suite)
        var setting = appSettings.setting
        setting.pageTranslationSourceAddress = ""
        let settings = SettingsStore(defaults: defaults)
        settings.apply(setting)
        return settings
    }()

    /// Writes the sample's folder, once per launch, before the store first reads it.
    static func prepare() async {
        guard let state = atLaunch, !isPrepared else { return }
        isPrepared = true
        await write(state, catalog: catalog, root: root)
    }

    @concurrent
    private nonisolated static func write(_ state: Self, catalog: ModelCatalog, root: URL) async {
        let files = FileManager()
        try? files.removeItem(at: root)
        let defaultSet: [ModelArtifactID] = [.k2xl, .cpt2, .jmtFast1, .lamaManga]
        let installed: [ModelArtifactID] = switch state {
        case .ready: defaultSet + [.v4s, .hyMT2]
        case .partial, .paused, .downloading, .offline, .noSpace, .failed: [.cpt2, .jmtFast1, .lamaManga]
        case .empty, .noSource, .publicStore: []
        case .preparing: defaultSet
        }
        switch state {
        case .paused: writeDownload(of: .k2xl, isPaused: true, catalog: catalog, root: root)
        case .downloading, .offline, .noSpace, .failed: writeDownload(of: .k2xl, isPaused: false, catalog: catalog, root: root)
        case .ready, .partial, .empty, .preparing, .noSource, .publicStore: break
        }
        for id in installed {
            guard let artifact = catalog.artifact(id) else { continue }
            let folder = root.appending(path: id.rawValue, directoryHint: .isDirectory)
            try? files.createDirectory(at: folder, withIntermediateDirectories: true)
            let isCoreML = if case .coreML = artifact.loading { true } else { false }
            let item = isCoreML ? "Sample.mlmodelc" : "sample.gguf"
            files.createFile(atPath: folder.appending(path: item).path(percentEncoded: false), contents: nil)
            if artifact.licenceFile != nil {
                let text = "The full text of \(artifact.credit.licence), as the file beside the model holds it."
                files.createFile(atPath: folder.appending(path: "LICENSE").path(percentEncoded: false), contents: Data(text.utf8))
            }
            let record: [String: Any] = [
                "catalogVersion": catalog.version, "artifact": id.rawValue, "version": artifact.version,
                "items": [["path": item, "isCompiledModel": isCoreML]],
                "bytes": artifact.downloadSize, "isPrepared": state != .preparing || !isCoreML
            ]
            if let data = try? JSONSerialization.data(withJSONObject: record) {
                files.createFile(atPath: folder.appending(path: "installed.json").path(percentEncoded: false), contents: data)
            }
        }
    }

    /// A download the store finds when it reads the folder, paused or going on: what was
    /// asked for, and a sparse part of the first file, a third of it.
    private nonisolated static func writeDownload(of id: ModelArtifactID, isPaused: Bool, catalog: ModelCatalog, root: URL) {
        guard let file = catalog.artifact(id)?.files.first else { return }
        let files = FileManager()
        let part = root.appending(path: id.rawValue, directoryHint: .isDirectory).appending(path: file.path + ".part")
        try? files.createDirectory(at: part.deletingLastPathComponent(), withIntermediateDirectories: true)
        files.createFile(atPath: part.path(percentEncoded: false), contents: nil)
        if let handle = try? FileHandle(forWritingTo: part) {
            try? handle.truncate(atOffset: UInt64(file.size / 3))
            try? handle.close()
        }
        let intent: [String: Any] = ["artifacts": [id.rawValue], "isPaused": isPaused]
        if let data = try? JSONSerialization.data(withJSONObject: intent) {
            files.createFile(atPath: root.appending(path: "downloads.json").path(percentEncoded: false), contents: data)
        }
    }

    /// The app's catalog with the four language models after the default translator. Their
    /// sizes are the files' own; their checksums are made up, as nothing is downloaded.
    private static let catalog: ModelCatalog = {
        var artifacts = ModelCatalog.generated.artifacts
        let index = (artifacts.firstIndex { $0.id == .jmtFast1 } ?? artifacts.count - 1) + 1
        artifacts.insert(contentsOf: languageModels, at: index)
        return ModelCatalog(version: ModelCatalog.generated.version, artifacts: artifacts)
    }()

    private static let languageModels: [ModelArtifact] = [
        languageModel(.galTransl4B, .publicStore, "GalTransl-v4-4B-2601", "SakuraLLM", "CC BY-NC-SA 4.0", 2_497_276_512, true),
        languageModel(
            .sakura1_5B, .fromPublisher, "Sakura-1.5B-Qwen2.5-v1.0 (Q5_K_S quantization)",
            "SakuraLLM (model); shing3232 (this quantized file)", "CC BY-NC-SA 4.0", 1_259_173_504, true
        ),
        languageModel(.hyMT2, .fromPublisher, "Hy-MT2 1.8B (GGUF)", "Tencent", "Apache-2.0", 1_133_080_448, false),
        languageModel(
            .qwen35_4B, .fromPublisher, "Qwen3.5 4B (IQ4_XS GGUF)", "Alibaba (model); unsloth (quantization)",
            "Apache-2.0", 2_477_053_088, false
        )
    ]

    private static func languageModel(
        _ id: ModelArtifactID, _ sharing: ArtifactSharing, _ name: String, _ author: String, _ licence: String,
        _ size: Int64, _ nonCommercial: Bool
    ) -> ModelArtifact {
        let sample = URL(string: "https://models.example/\(id.rawValue)")!
        return ModelArtifact(
            id: id, version: "1", role: .translator, sharing: sharing,
            credit: ArtifactCredit(
                name: name, author: author, source: sample, licence: licence, licenceText: sample, changes: nil,
                nonCommercial: nonCommercial
            ),
            loading: .languageModel(promptFamily: id.rawValue),
            publisherAddresses: sharing == .fromPublisher ? [sample] : [],
            files: [ModelFile("model.gguf", size, String(repeating: "0", count: 64))]
        )
    }
}

/// Serves zeros at 256 KB/s for each range (`-PageTranslationSampleRate <KB/s>` changes it),
/// and no range in less than 45 s, so even a small file is under way long enough to be seen;
/// each range is written as a sparse file. A download moves on screen, writes nothing for a
/// while, and fails its checksum at the end. With `refuses` every range is answered with a
/// 404 at once.
nonisolated private struct SampleTransport: ModelTransport {
    var refuses = false

    private static let bytesPerSecond: Double = {
        let rate = UserDefaults.standard.integer(forKey: "PageTranslationSampleRate")
        return Double(rate > 0 ? rate : 256) * 1024
    }()
    private static let shortest = 45.0
    private static let stepsPerSecond = 8.0

    func fetch(
        _ request: ModelChunkRequest, received: @escaping @Sendable (Int64) -> Void
    ) async throws -> ModelChunkOutcome {
        if refuses { return .refused(status: 404, retryAfter: nil) }
        let count = Int64(request.range.count)
        let seconds = max(Double(count) / Self.bytesPerSecond, Self.shortest)
        let steps = Int(seconds * Self.stepsPerSecond)
        for step in 1...steps {
            try await Task.sleep(for: .seconds(1 / Self.stepsPerSecond))
            received(count * Int64(step) / Int64(steps))
        }
        let files = FileManager()
        try files.createDirectory(at: request.destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        files.createFile(atPath: request.destination.path(percentEncoded: false), contents: nil)
        let handle = try FileHandle(forWritingTo: request.destination)
        try handle.truncate(atOffset: UInt64(count))
        try handle.close()
        return .finished
    }
}
#endif
