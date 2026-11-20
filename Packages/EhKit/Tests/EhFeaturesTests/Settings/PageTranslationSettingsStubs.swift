import CryptoKit
import Dependencies
import EhCore
import EhFeatures
import EhModels
import Foundation
import Synchronization
import Testing

// A model store over a temporary folder and a small catalog, with a transport that serves
// files from memory and can hold a download halfway, so the Settings model is tested
// against the real store rather than a mock of it.

/// Seven small artifacts under the real names, so the settings' choices find them. A range
/// is 256 bytes here.
nonisolated enum TranslationSamples {
    static let chunkSize: Int64 = 256
    static let privateStore = URL(string: "https://private.example/models")!
    static let publisher = URL(string: "https://author.example/model/resolve/abc123")!
    static let token = "made-up-token"

    static func bytes(_ count: Int, seed: UInt8) -> Data {
        var data = Data(count: count)
        var value = UInt32(seed) &* 2_654_435_761 &+ 1
        for index in 0..<count {
            value = value &* 1_664_525 &+ 1_013_904_223
            data[index] = UInt8(truncatingIfNeeded: value >> 24)
        }
        return data
    }

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Each artifact's files, by path: a model file and, for most, its licence.
    static let contents: [ModelArtifactID: [(path: String, data: Data)]] = [
        .k2xl: [("model.bin", bytes(700, seed: 1)), ("LICENSE", Data("The detector's licence.".utf8))],
        .yolo26s: [("model.bin", bytes(600, seed: 2)), ("LICENSE", Data("The second detector's licence.".utf8))],
        .v4s: [("model.bin", bytes(500, seed: 3)), ("LICENSE", Data("Apache License 2.0".utf8))],
        .cpt2: [("model.bin", bytes(900, seed: 4)), ("LICENSE", Data("CC BY-NC-SA 4.0".utf8))],
        .jmtFast1: [("model.bin", bytes(800, seed: 5))],
        .galTransl4B: [("model.gguf", bytes(1300, seed: 6)), ("LICENSE", Data("CC BY-NC-SA 4.0".utf8))],
        .lamaManga: [("model.bin", bytes(400, seed: 7)), ("LICENSE", Data("MIT".utf8))]
    ]

    static func files(of id: ModelArtifactID) -> [ModelFile] {
        (contents[id] ?? []).map { ModelFile($0.path, Int64($0.data.count), sha256($0.data)) }
    }

    static func size(of id: ModelArtifactID) -> Int64 {
        files(of: id).reduce(0) { $0 + $1.size }
    }

    static func credit(_ name: String, nonCommercial: Bool = false) -> ArtifactCredit {
        ArtifactCredit(
            name: name, author: "An author of \(name)", source: URL(string: "https://author.example/\(name)")!,
            licence: nonCommercial ? "CC BY-NC-SA 4.0" : "Apache-2.0",
            licenceText: URL(string: "https://author.example/licence")!,
            changes: nonCommercial ? nil : "Converted to Core ML.", nonCommercial: nonCommercial
        )
    }

    private static func artifact(
        _ id: ModelArtifactID, _ role: ModelRole, _ sharing: ArtifactSharing, _ name: String,
        nonCommercial: Bool = false
    ) -> ModelArtifact {
        ModelArtifact(
            id: id, version: "1", role: role, sharing: sharing, credit: credit(name, nonCommercial: nonCommercial),
            // Plain files: nothing to compile, nothing to load once.
            loading: .languageModel(promptFamily: "test"),
            publisherAddresses: sharing == .fromPublisher ? [publisher] : [], files: files(of: id)
        )
    }

    /// In the real catalog's order. RTMDet2, nar-small, three language models and big-lama
    /// are not listed, like the language models of the real catalog today.
    static let catalog = ModelCatalog(version: 3, artifacts: [
        artifact(.k2xl, .detector, .privateOnly, "Detector A"),
        artifact(.yolo26s, .detector, .privateOnly, "Detector B"),
        artifact(.v4s, .detector, .publicStore, "Detector C"),
        artifact(.cpt2, .reader, .publicStore, "Reader", nonCommercial: true),
        artifact(.jmtFast1, .translator, .fromPublisher, "Translator", nonCommercial: true),
        artifact(.galTransl4B, .translator, .publicStore, "Language model", nonCommercial: true),
        artifact(.lamaManga, .repaint, .publicStore, "Repaint")
    ])

    static func temporaryFolder() -> URL {
        URL.temporaryDirectory.appending(path: "TranslationSettingsTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    }
}

/// Serves model files from memory; a held address answers only once it is released or the
/// request is cancelled.
nonisolated final class TranslationStubTransport: ModelTransport {
    private struct State {
        var files: [URL: Data] = [:]
        var held: Set<URL> = []
        var waiting: [UUID: (url: URL, resume: CheckedContinuation<Void, Never>)] = [:]
        var requests: [URL] = []
    }

    private let state = Mutex(State())

    var requests: [URL] { state.withLock { $0.requests } }

    func publish(_ data: Data, at url: URL) {
        state.withLock { $0.files[url] = data }
    }

    func hold(_ url: URL) {
        state.withLock { _ = $0.held.insert(url) }
    }

    func release(_ url: URL) {
        let waiters = state.withLock { state in
            state.held.remove(url)
            let matching = state.waiting.filter { $0.value.url == url }
            for key in matching.keys { state.waiting[key] = nil }
            return matching.values.map(\.resume)
        }
        for waiter in waiters { waiter.resume() }
    }

    /// Whether a request for `url` has arrived and waits.
    func isWaiting(at url: URL) -> Bool {
        state.withLock { $0.waiting.values.contains { $0.url == url } }
    }

    func fetch(
        _ request: ModelChunkRequest, received: @escaping @Sendable (Int64) -> Void
    ) async throws -> ModelChunkOutcome {
        let isHeld = state.withLock { state in
            state.requests.append(request.url)
            return state.held.contains(request.url)
        }
        if isHeld { try await waitForRelease(of: request.url) }
        guard let data = state.withLock({ $0.files[request.url] }) else { return .refused(status: 404, retryAfter: nil) }
        guard request.range.lowerBound < Int64(data.count) else { return .refused(status: 416, retryAfter: nil) }
        let bytes = data.subdata(in: Int(request.range.lowerBound)..<min(Int(request.range.upperBound), data.count))
        try FileManager.default.createDirectory(
            at: request.destination.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try bytes.write(to: request.destination)
        received(Int64(bytes.count))
        return .finished
    }

    private func waitForRelease(of url: URL) async throws {
        let id = UUID()
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let stillHeld = state.withLock { state in
                    guard state.held.contains(url) else { return false }
                    state.waiting[id] = (url, continuation)
                    return true
                }
                if !stillHeld { continuation.resume() }
            }
        } onCancel: {
            let waiter = state.withLock { $0.waiting.removeValue(forKey: id) }
            waiter?.resume.resume()
        }
        try Task.checkCancellation()
    }
}

/// The store, its folder and its transport, with the private store set up unless told
/// otherwise.
@MainActor
final class TranslationStoreHarness {
    let root = TranslationSamples.temporaryFolder()
    let transport = TranslationStubTransport()
    let tokens: ModelSourceTokenStore
    let settings: SettingsStore
    /// The artifacts whose files were put in place.
    private(set) var copied: Set<ModelArtifactID> = []
    private(set) lazy var store = PageTranslationModelStore(
        environment: ModelStoreEnvironment(
            catalog: TranslationSamples.catalog,
            layout: ModelStoreLayout(root: root),
            transport: transport,
            compiler: ModelCompiler(compile: { $0 }, prepare: { _, _ in }),
            tokens: tokens,
            publicStore: nil,
            freeSpace: { _ in .max },
            chunkSize: TranslationSamples.chunkSize,
            sleep: { _ in }
        ),
        choices: .settings(settings)
    )

    init(privateStore: Bool = true) {
        settings = SettingsStore.ephemeral()
        tokens = .inMemory(privateStore ? TranslationSamples.token : nil)
        if privateStore { settings.pageTranslationSourceAddress = TranslationSamples.privateStore.absoluteString }
        for (id, files) in TranslationSamples.contents {
            for file in files {
                transport.publish(file.data, at: address(of: file.path, in: id))
            }
        }
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    /// Where the store asks for a file first: the publisher for the translator, the
    /// private store for everything else.
    func address(of path: String, in id: ModelArtifactID) -> URL {
        if id == .jmtFast1 { return TranslationSamples.publisher.appending(path: path) }
        return TranslationSamples.privateStore.appending(path: "\(id.rawValue)/1/\(path)")
    }

    /// Holds the first file of an artifact, so its download stays under way.
    func hold(_ id: ModelArtifactID) {
        guard let path = TranslationSamples.contents[id]?.first?.path else { return }
        transport.hold(address(of: path, in: id))
    }

    func release(_ id: ModelArtifactID) {
        guard let path = TranslationSamples.contents[id]?.first?.path else { return }
        transport.release(address(of: path, in: id))
    }

    func isWaiting(_ id: ModelArtifactID) -> Bool {
        guard let path = TranslationSamples.contents[id]?.first?.path else { return false }
        return transport.isWaiting(at: address(of: path, in: id))
    }

    /// Puts an artifact's files in place as if they had been copied in; `refresh()`
    /// adopts them.
    func copyIn(_ ids: [ModelArtifactID]) throws {
        let layout = ModelStoreLayout(root: root)
        copied.formUnion(ids)
        for id in ids {
            for (path, data) in TranslationSamples.contents[id] ?? [] {
                let url = layout.url(ofPath: path, in: id)
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: url)
            }
        }
    }

    /// The default choices' four models installed, with whatever else was copied in.
    func installDefaultSet() async throws {
        try copyIn([.k2xl, .cpt2, .jmtFast1, .lamaManga])
        await store.refresh()
        await waitFor("the models copied in are installed") {
            self.copied.allSatisfy { self.store.state(of: $0) == .installed }
        }
    }

    /// The Translation screen's model over this store and settings, with the page cache's
    /// writer and patch store when a test gives them.
    func makeModel(
        cache: (writer: PageTranslationResultWriter, patches: PageTranslationPatchStore)? = nil
    ) -> PageTranslationSettingsModel {
        withDependencies {
            $0.settings = settings
            $0.pageTranslationModelStore = store
            if let cache {
                $0.pageTranslationResultWriter = cache.writer
                $0.pageTranslationPatchStore = cache.patches
            }
        } operation: {
            PageTranslationSettingsModel()
        }
    }

    func folderExists(of id: ModelArtifactID) -> Bool {
        FileManager.default.fileExists(atPath: ModelStoreLayout(root: root).folder(of: id).path(percentEncoded: false))
    }
}

/// Waits until `condition` holds. The deadline is long because this Mac is often busy.
@MainActor
func waitFor(
    _ what: String, timeout: Duration = .seconds(60), _ condition: @MainActor () -> Bool,
    sourceLocation: SourceLocation = #_sourceLocation
) async {
    let deadline = ContinuousClock.now + timeout
    while !condition() {
        guard ContinuousClock.now < deadline else {
            Issue.record("Timed out waiting until \(what)", sourceLocation: sourceLocation)
            return
        }
        try? await Task.sleep(for: .milliseconds(5))
    }
}
