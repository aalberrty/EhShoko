import CryptoKit
import EhModels
import Foundation
import Synchronization
import Testing
@testable import EhCore

/// Whether the caller runs on the main thread. A function of its own because the property
/// may not be read from asynchronous code directly.
func isOnMainThread() -> Bool {
    Thread.isMainThread
}

// MARK: A transport that serves from memory

/// Serves model files from memory and records every request, the way site tests stub the
/// HTTP transport. A file is published at an address; anything else answers 404.
final class StubModelTransport: ModelTransport {
    struct Request: Sendable, Equatable {
        var url: URL
        var range: Range<Int64>
        var token: String?
    }

    enum Answer: Sendable {
        /// Answers with this status instead of the file.
        case status(Int, retryAfter: Duration? = nil)
        /// Fails the connection.
        case error(URLError.Code)
        /// Never answers; ends only when the request is cancelled.
        case hang
    }

    private struct State {
        var files: [URL: Data] = [:]
        /// Answers given before the file, first in first out, for each address.
        var scripted: [URL: [Answer]] = [:]
        /// Addresses that never answer from this range on.
        var hanging: [URL: Int64] = [:]
        var requests: [Request] = []
        var mainThreadCalls = 0
        var ownedSession: String?
        var eventsDelivered: (@Sendable () -> Void)?
        var collected = 0
    }

    private let state = Mutex(State())

    func publish(_ data: Data, at url: URL) {
        state.withLock { $0.files[url] = data }
    }

    func withdraw(_ url: URL) {
        state.withLock { $0.files[url] = nil }
    }

    func script(_ answers: [Answer], at url: URL) {
        state.withLock { $0.scripted[url, default: []] += answers }
    }

    /// Requests for `url` from the range starting at `offset` on never answer.
    func hang(_ url: URL, from offset: Int64 = 0) {
        state.withLock { $0.hanging[url] = offset }
    }

    func release(_ url: URL) {
        state.withLock { $0.hanging[url] = nil }
    }

    var requests: [Request] { state.withLock { $0.requests } }
    var mainThreadCalls: Int { state.withLock { $0.mainThreadCalls } }
    var collected: Int { state.withLock { $0.collected } }

    func requests(to host: String) -> [Request] {
        requests.filter { $0.url.host() == host }
    }

    func clearRequests() {
        state.withLock { $0.requests = [] }
    }

    func fetch(
        _ request: ModelChunkRequest, received: @escaping @Sendable (Int64) -> Void
    ) async throws -> ModelChunkOutcome {
        let onMainThread = isOnMainThread()
        let (answer, data, hangs) = state.withLock { state -> (Answer?, Data?, Bool) in
            state.requests.append(Request(url: request.url, range: request.range, token: request.token))
            if onMainThread { state.mainThreadCalls += 1 }
            if let offset = state.hanging[request.url], request.range.lowerBound >= offset { return (nil, nil, true) }
            if var answers = state.scripted[request.url], !answers.isEmpty {
                let answer = answers.removeFirst()
                state.scripted[request.url] = answers
                return (answer, nil, false)
            }
            return (nil, state.files[request.url], false)
        }
        if hangs { return try await Self.never() }
        switch answer {
        case .status(let status, let retryAfter): return .refused(status: status, retryAfter: retryAfter)
        case .error(let code): throw URLError(code)
        case .hang: return try await Self.never()
        case nil: break
        }
        guard let data else { return .refused(status: 404, retryAfter: nil) }
        guard request.range.lowerBound < Int64(data.count) else { return .refused(status: 416, retryAfter: nil) }
        let upper = min(Int(request.range.upperBound), data.count)
        let bytes = data.subdata(in: Int(request.range.lowerBound)..<upper)
        received(Int64(bytes.count / 2))
        try FileManager.default.createDirectory(
            at: request.destination.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try bytes.write(to: request.destination)
        received(Int64(bytes.count))
        return .finished
    }

    private static func never() async throws -> ModelChunkOutcome {
        try await Task.sleep(for: .seconds(3600))
        return .refused(status: 0, retryAfter: nil)
    }

    // Background events: the stub owns the session a test names.

    func own(session identifier: String) {
        state.withLock { $0.ownedSession = identifier }
    }

    func deliverEvents() {
        state.withLock { state in
            defer { state.eventsDelivered = nil }
            return state.eventsDelivered
        }?()
    }

    func collectEarlierTransfers() async {
        state.withLock { $0.collected += 1 }
    }

    func handleBackgroundEvents(identifier: String, delivered: @escaping @Sendable () -> Void) -> Bool {
        state.withLock { state in
            guard state.ownedSession == identifier else { return false }
            state.eventsDelivered = delivered
            return true
        }
    }
}

// MARK: A compiler that copies

/// Stands in for Core ML: "compiling" a package writes a folder that names it.
final class StubCompiler: Sendable {
    private struct State {
        var compiled: [String] = []
        var prepared: [(String, ModelComputeUnits)] = []
        var mainThreadCalls = 0
        var compileError: (any Error)?
        var prepareError: (any Error)?
        var gate: AsyncStream<Void>?
    }

    private let state = Mutex(State())

    var compiled: [String] { state.withLock { $0.compiled } }
    var prepared: [String] { state.withLock { $0.prepared.map(\.0) } }
    var preparedUnits: [ModelComputeUnits] { state.withLock { $0.prepared.map(\.1) } }
    var mainThreadCalls: Int { state.withLock { $0.mainThreadCalls } }

    func failCompiling(_ error: (any Error)?) {
        state.withLock { $0.compileError = error }
    }

    func failPreparing(_ error: (any Error)?) {
        state.withLock { $0.prepareError = error }
    }

    /// Makes compiling wait until the returned continuation finishes.
    func holdCompiling() -> AsyncStream<Void>.Continuation {
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        state.withLock { $0.gate = stream }
        return continuation
    }

    var compiler: ModelCompiler {
        ModelCompiler(
            compile: { [self] package in
                let onMainThread = isOnMainThread()
                let (error, gate) = state.withLock { state in
                    state.compiled.append(package.lastPathComponent)
                    if onMainThread { state.mainThreadCalls += 1 }
                    return (state.compileError, state.gate)
                }
                if let gate { for await _ in gate {} }
                if let error { throw error }
                let output = URL.temporaryDirectory
                    .appending(path: "compiled-\(UUID().uuidString)", directoryHint: .isDirectory)
                    .appending(path: package.deletingPathExtension().lastPathComponent + ".mlmodelc", directoryHint: .isDirectory)
                try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
                // A compiled model is about the size of its package.
                let weights = package.appending(path: "Data/com.apple.CoreML/weights/weight.bin")
                try FileManager.default.copyItem(at: weights, to: output.appending(path: "weights.bin"))
                return output
            },
            prepare: { [self] model, units in
                let onMainThread = isOnMainThread()
                let error = state.withLock { state in
                    state.prepared.append((model.lastPathComponent, units))
                    if onMainThread { state.mainThreadCalls += 1 }
                    return state.prepareError
                }
                if let error { throw error }
            }
        )
    }
}

// MARK: A small catalog

/// A catalog of six small artifacts under the real names, so the choices of the settings
/// find them. A range is 1,024 bytes in these tests.
enum StoreSamples {
    static let chunkSize: Int64 = 1024
    static let privateStore = URL(string: "https://private.example/models")!
    static let publicStore = URL(string: "https://public.example/models")!
    static let publisher = URL(string: "https://author.example/model/resolve/abc123")!
    static let mirror = URL(string: "https://mirror.example/model/resolve/master")!
    static let token = "made-up-token"

    /// Bytes that differ from file to file and from range to range.
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

    static func credit(_ name: String, nonCommercial: Bool = false) -> ArtifactCredit {
        ArtifactCredit(
            name: name, author: "An author", source: URL(string: "https://author.example/\(name)")!,
            licence: nonCommercial ? "CC BY-NC-SA 4.0" : "Apache-2.0",
            licenceText: URL(string: "https://author.example/licence")!, changes: "Converted to Core ML.",
            nonCommercial: nonCommercial
        )
    }

    /// The contents of each artifact's files, by path.
    static let contents: [ModelArtifactID: [(path: String, data: Data)]] = [
        .k2xl: package("K2XL.mlpackage", weights: 5300, seed: 1) + notices(seed: 2),
        .v4s: package("V4S.mlpackage", weights: 2100, seed: 3) + notices(seed: 4),
        .cpt2: package("Encoder.mlpackage", weights: 4096, seed: 5) + package("Decoder.mlpackage", weights: 1500, seed: 6)
            + [("vocab.txt", bytes(700, seed: 7))] + notices(seed: 8),
        .jmtFast1: package("coreml/decoder.mlpackage", weights: 3000, seed: 9) + [
            ("coreml/host/table.npy", bytes(2500, seed: 10)), ("tokenizer/tokenizer.json", bytes(300, seed: 11))
        ],
        .galTransl4B: [("model.gguf", bytes(10_500, seed: 12))] + notices(seed: 13),
        .lamaManga: package("LaMa.mlpackage", weights: 2048, seed: 14) + notices(seed: 15)
    ]

    private static func package(_ name: String, weights: Int, seed: UInt8) -> [(path: String, data: Data)] {
        [
            ("\(name)/Manifest.json", bytes(61, seed: seed)),
            ("\(name)/Data/com.apple.CoreML/model.mlmodel", bytes(900, seed: seed &+ 100)),
            ("\(name)/Data/com.apple.CoreML/weights/weight.bin", bytes(weights, seed: seed &+ 200))
        ]
    }

    private static func notices(seed: UInt8) -> [(path: String, data: Data)] {
        [("LICENSE", bytes(400, seed: seed)), ("CREDITS.md", bytes(120, seed: seed &+ 50))]
    }

    static func files(of id: ModelArtifactID) -> [ModelFile] {
        (contents[id] ?? []).map { ModelFile($0.path, Int64($0.data.count), sha256($0.data)) }
    }

    static func data(_ path: String, of id: ModelArtifactID) -> Data {
        contents[id]?.first { $0.path == path }?.data ?? Data()
    }

    static let catalog = ModelCatalog(version: 7, artifacts: [
        ModelArtifact(
            id: .k2xl, version: "1", role: .detector, sharing: .privateOnly,
            credit: credit("Detector A", nonCommercial: true), loading: .coreML(.cpuAndNeuralEngine), files: files(of: .k2xl)
        ),
        ModelArtifact(
            id: .v4s, version: "2", role: .detector, sharing: .publicStore, credit: credit("Detector B"),
            loading: .coreML(.cpuOnly), files: files(of: .v4s)
        ),
        ModelArtifact(
            id: .cpt2, version: "1", role: .reader, sharing: .publicStore, credit: credit("Reader", nonCommercial: true),
            loading: .coreML(.cpuAndNeuralEngine), files: files(of: .cpt2)
        ),
        ModelArtifact(
            id: .jmtFast1, version: "1", role: .translator, sharing: .fromPublisher,
            credit: credit("Translator", nonCommercial: true), loading: .coreML(.cpuAndNeuralEngine),
            publisherAddresses: [publisher, mirror], files: files(of: .jmtFast1)
        ),
        ModelArtifact(
            id: .galTransl4B, version: "1", role: .translator, sharing: .publicStore,
            credit: credit("Language model", nonCommercial: true), loading: .languageModel(promptFamily: "galtransl"),
            files: files(of: .galTransl4B)
        ),
        ModelArtifact(
            id: .lamaManga, version: "1", role: .repaint, sharing: .publicStore, credit: credit("Repaint"),
            loading: .coreML(.cpuAndGPU), files: files(of: .lamaManga)
        )
    ])

    static func artifact(_ id: ModelArtifactID) -> ModelArtifact {
        catalog.artifact(id)!
    }

    static func temporaryFolder() -> URL {
        URL.temporaryDirectory.appending(path: "ModelStoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    }
}

// MARK: A store with everything stubbed

/// The settings a test changes.
@MainActor
final class StoreChoices {
    var modelSet = PageTranslationModelSet.default
    var repaint = RepaintChoice.default
    var sourceAddress = ""

    var choices: ModelStoreChoices {
        ModelStoreChoices(
            modelSet: { self.modelSet }, repaint: { self.repaint }, sourceAddress: { self.sourceAddress }
        )
    }
}

/// A value tests change from outside and closures read from anywhere.
final class Shared<Value: Sendable>: Sendable {
    private let value: Mutex<Value>

    init(_ value: Value) {
        self.value = Mutex(value)
    }

    func get() -> Value { value.withLock { $0 } }
    func set(_ new: Value) { value.withLock { $0 = new } }
    func update(_ change: (inout Value) -> Void) { value.withLock { change(&$0) } }
}

@MainActor
final class StoreHarness {
    let root: URL
    let transport: StubModelTransport
    let compiler = StubCompiler()
    let tokens: ModelSourceTokenStore
    let settings = StoreChoices()
    let freeSpace = Shared<Int64>(.max)
    let logs = Shared<[String]>([])
    /// The waits the store asked for, which these tests do not sit through.
    let waits = Shared<[Duration]>([])
    let connectivity: AsyncStream<Bool>.Continuation
    private let connectivityStream: AsyncStream<Bool>
    private(set) lazy var store = makeStore()
    var publicStore: URL?
    var chunksInFlight = 96

    /// A store with a private store address and its token set, unless told otherwise.
    init(
        privateStore: Bool = true, publicStore: URL? = nil, root: URL = StoreSamples.temporaryFolder(),
        transport: StubModelTransport = StubModelTransport()
    ) {
        self.root = root
        self.transport = transport
        self.publicStore = publicStore
        tokens = ModelSourceTokenStore.inMemory(privateStore ? StoreSamples.token : nil)
        if privateStore { settings.sourceAddress = StoreSamples.privateStore.absoluteString }
        (connectivityStream, connectivity) = AsyncStream<Bool>.makeStream()
    }

    /// Another store over the same folder and transport: the app started again.
    func makeStore() -> PageTranslationModelStore {
        let freeSpace = freeSpace
        let logs = logs
        let waits = waits
        let stream = connectivityStream
        let environment = ModelStoreEnvironment(
            catalog: StoreSamples.catalog,
            layout: ModelStoreLayout(root: root),
            transport: transport,
            compiler: compiler.compiler,
            tokens: tokens,
            publicStore: publicStore,
            freeSpace: { _ in freeSpace.get() },
            connectivity: { stream },
            log: { line in logs.update { $0.append(line) } },
            chunkSize: StoreSamples.chunkSize,
            chunksInFlight: chunksInFlight,
            sleep: { duration in waits.update { $0.append(duration) } }
        )
        return PageTranslationModelStore(environment: environment, choices: settings.choices)
    }

    var layout: ModelStoreLayout { ModelStoreLayout(root: root) }

    /// Publishes an artifact's files at a store's address.
    func publish(_ id: ModelArtifactID, at store: URL, corrupting corrupted: Set<String> = []) {
        let artifact = StoreSamples.artifact(id)
        for (path, data) in StoreSamples.contents[id] ?? [] {
            var data = data
            if corrupted.contains(path) { data[data.count / 2] ^= 0xFF }
            transport.publish(data, at: store.appending(path: "\(id.rawValue)/\(artifact.version)/\(path)"))
        }
    }

    /// Publishes an artifact's files where its author offers them.
    func publish(_ id: ModelArtifactID, atPublisher address: URL) {
        for (path, data) in StoreSamples.contents[id] ?? [] {
            transport.publish(data, at: address.appending(path: path))
        }
    }

    /// Everything the default choices need, where the owner gets it: the private store and
    /// the translator's author.
    func publishDefaultSet() {
        for id in [ModelArtifactID.k2xl, .cpt2, .lamaManga] { publish(id, at: StoreSamples.privateStore) }
        publish(.jmtFast1, atPublisher: StoreSamples.publisher)
    }

    /// Puts an artifact's files in place as if they had been copied in.
    func copyIn(_ id: ModelArtifactID, corrupting corrupted: Set<String> = []) throws {
        for (path, data) in StoreSamples.contents[id] ?? [] {
            var data = data
            if corrupted.contains(path) { data[0] ^= 0xFF }
            let url = layout.url(ofPath: path, in: id)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url)
        }
    }

    func exists(_ path: String, in id: ModelArtifactID) -> Bool {
        FileManager.default.fileExists(atPath: layout.url(ofPath: path, in: id).path(percentEncoded: false))
    }

    /// The files under an artifact's folder, as sorted relative paths.
    func files(in id: ModelArtifactID) -> [String] {
        let folder = layout.folder(of: id).standardizedFileURL.path(percentEncoded: false)
        guard let paths = FileManager.default.subpaths(atPath: folder) else { return [] }
        return paths.filter { path in
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: folder + "/" + path, isDirectory: &isDirectory)
                && !isDirectory.boolValue
        }.sorted()
    }

    /// The address of one of an artifact's files at a store.
    func address(of path: String, in id: ModelArtifactID, at store: URL = StoreSamples.privateStore) -> URL {
        store.appending(path: "\(id.rawValue)/\(StoreSamples.artifact(id).version)/\(path)")
    }
}

/// Waits until `condition` holds. The deadline is long because this Mac is often busy.
@MainActor
func waitUntil(
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
