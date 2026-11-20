#if DEBUG
import Dependencies
import EhCore
import EhFeatures
import EhModels
import Foundation

/// Settings › Translation on a store of its own, for screenshots and the scroll check: launch
/// a debug build with `-PageTranslationSample <state>`.
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
enum PageTranslationSample: String {
    case ready, partial, empty, preparing, paused

    static let atLaunch = UserDefaults.standard.string(forKey: "PageTranslationSample").flatMap(Self.init)

    private static let root = URL.temporaryDirectory.appending(path: "PageTranslationSample", directoryHint: .isDirectory)
    private static var isPrepared = false

    /// The one sample store of the process.
    private static let store: PageTranslationModelStore? = atLaunch.map { _ in
        @Dependency(\.settings) var settings
        let environment = ModelStoreEnvironment(
            catalog: catalog,
            layout: ModelStoreLayout(root: root),
            transport: SampleTransport(),
            compiler: ModelCompiler(
                compile: { $0 },
                prepare: { _, _ in try await Task.sleep(for: .seconds(atLaunch == .preparing ? 20 : 0)) }
            ),
            tokens: .inMemory(),
            freeSpace: { _ in 64_000_000_000 }
        )
        return PageTranslationModelStore(environment: environment, choices: .settings(settings))
    }

    /// The Translation screen's model over the sample store, or `nil` without the argument.
    static func makeModel() -> PageTranslationSettingsModel? {
        guard let store else { return nil }
        return withDependencies { $0.pageTranslationModelStore = store } operation: {
            PageTranslationSettingsModel()
        }
    }

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
        case .partial, .paused: [.cpt2, .jmtFast1, .lamaManga]
        case .empty: []
        case .preparing: defaultSet
        }
        if state == .paused { writePausedDownload(of: .k2xl, catalog: catalog, root: root) }
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

    /// A download the store finds paused when it reads the folder: what was asked for, and a
    /// sparse part of the first file, a third of it.
    private nonisolated static func writePausedDownload(of id: ModelArtifactID, catalog: ModelCatalog, root: URL) {
        guard let file = catalog.artifact(id)?.files.first else { return }
        let files = FileManager()
        let part = root.appending(path: id.rawValue, directoryHint: .isDirectory).appending(path: file.path + ".part")
        try? files.createDirectory(at: part.deletingLastPathComponent(), withIntermediateDirectories: true)
        files.createFile(atPath: part.path(percentEncoded: false), contents: nil)
        if let handle = try? FileHandle(forWritingTo: part) {
            try? handle.truncate(atOffset: UInt64(file.size / 3))
            try? handle.close()
        }
        let intent: [String: Any] = ["artifacts": [id.rawValue], "isPaused": true]
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
            .sakura1_5B, .privateOnly, "Sakura-1.5B-Qwen2.5-v1.0 (Q5_K_S quantization)",
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
/// while, and fails its checksum at the end.
nonisolated private struct SampleTransport: ModelTransport {
    private static let bytesPerSecond: Double = {
        let rate = UserDefaults.standard.integer(forKey: "PageTranslationSampleRate")
        return Double(rate > 0 ? rate : 256) * 1024
    }()
    private static let shortest = 45.0
    private static let stepsPerSecond = 8.0

    func fetch(
        _ request: ModelChunkRequest, received: @escaping @Sendable (Int64) -> Void
    ) async throws -> ModelChunkOutcome {
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
