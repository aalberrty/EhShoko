import EhModels
import Foundation
import Synchronization
import Testing
@testable import EhCore

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
