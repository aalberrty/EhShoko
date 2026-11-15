import EhModels
import Foundation
import Synchronization

/// One file to fetch: where it goes and where it may come from, in order.
struct ModelFileJob: Sendable {
    var artifact: ModelArtifactID
    var file: ModelFile
    var sources: [ModelFileSource]
}

/// Downloads model files in ranges.
///
/// - Each file is fetched in ranges of 32 MiB, each a fresh request to the file's address:
///   a store may redirect to a signed address that expires, and a range is the most a
///   dropped connection can lose.
/// - Every range still missing is handed to the transport at once (up to `slots`), which is
///   what lets a download go on while the app is suspended. Ranges arrive in any order and
///   are appended to `<file>.part` in the file's order, hashed as they are appended.
/// - A file that does not match the catalog's SHA-256 is deleted and fetched from the next
///   source. A timeout, a 403, 404 or 5xx moves to the next source as well; a 429 waits as
///   long as the server asks.
struct ModelDownloader: Sendable {
    var transport: any ModelTransport
    var layout: ModelStoreLayout
    var chunkSize = ModelStoreEnvironment.standardChunkSize
    /// Bounds the ranges in flight across every file of every download.
    var slots: ModelWorkSlots
    /// How a 429 is waited out; tests replace it.
    var sleep: @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    /// The wait when a 429 names none, the longest wait, and how often one source is waited for.
    var retryPolicy = RetryPolicy()

    struct RetryPolicy: Sendable {
        var defaultWait: Duration = .seconds(5)
        var longestWait: Duration = .seconds(120)
        var waits = 5
    }

    /// Fetches `job`'s file into place, verified. Throws `ModelStoreFailure` when no source
    /// could provide it, `CancellationError` when the task was cancelled; what has arrived
    /// stays on disk for the next attempt either way.
    func download(_ job: ModelFileJob, progress: ModelDownloadProgress) async throws {
        var failure = ModelStoreFailure.noSource
        for source in job.sources {
            var attempt = 0
            while true {
                attempt += 1
                // Whether anything on disk predates this attempt and may come from elsewhere.
                let startsClean = !hasLeftovers(of: job)
                do {
                    try await fetch(job, from: source, progress: progress)
                    return
                } catch let problem as SourceProblem {
                    failure = problem.failure
                    guard problem == .checksumMismatch else { break }
                    discard(job)
                    progress.settle(job.file.path, bytes: 0)
                    // Bytes left by an earlier run may be what was wrong, not this source:
                    // it gets one more try from nothing.
                    if startsClean || attempt > 1 { break }
                }
            }
        }
        throw failure
    }

    /// Removes what a download of `job`'s file has left behind.
    func discard(_ job: ModelFileJob) {
        ModelFiles.remove(layout.partURL(of: job.file, in: job.artifact))
        for index in chunkRanges(of: job.file).indices {
            ModelFiles.remove(layout.chunkURL(of: job.file, in: job.artifact, index: index))
        }
    }

    /// The ranges of a file, in order.
    func chunkRanges(of file: ModelFile) -> [Range<Int64>] {
        guard file.size > 0 else { return [] }
        return stride(from: Int64(0), to: file.size, by: Int64.Stride(chunkSize)).map {
            $0..<min($0 + chunkSize, file.size)
        }
    }

    /// The bytes of `file` that are on disk already: its part file and the ranges waiting
    /// for their turn.
    func bytesOnDisk(of file: ModelFile, in artifact: ModelArtifactID) -> Int64 {
        let ranges = chunkRanges(of: file)
        let part = min(ModelFiles.size(of: layout.partURL(of: file, in: artifact)) ?? 0, file.size)
        let whole = Int(part / chunkSize)
        var total = part == file.size ? part : Int64(whole) * chunkSize
        for index in ranges.indices.dropFirst(whole) where part != file.size {
            let chunk = layout.chunkURL(of: file, in: artifact, index: index)
            if ModelFiles.size(of: chunk) == Int64(ranges[index].count) { total += Int64(ranges[index].count) }
        }
        return total
    }

    // MARK: One source

    private enum SourceProblem: Error, Equatable {
        case refused(status: Int)
        case unreachable
        case checksumMismatch

        var failure: ModelStoreFailure {
            switch self {
            case .refused(let status): .refused(status: status)
            case .unreachable: .unreachable
            case .checksumMismatch: .checksumMismatch
            }
        }
    }

    private func hasLeftovers(of job: ModelFileJob) -> Bool {
        bytesOnDisk(of: job.file, in: job.artifact) > 0
    }

    private func fetch(_ job: ModelFileJob, from source: ModelFileSource, progress: ModelDownloadProgress) async throws {
        let file = job.file
        let ranges = chunkRanges(of: file)
        let partURL = layout.partURL(of: file, in: job.artifact)
        let part = try ModelPartFile(url: partURL, chunkSize: chunkSize, fileSize: file.size)
        defer { part.close() }
        var next = part.length == file.size ? ranges.count : Int(part.length / chunkSize)
        progress.settle(file.path, bytes: part.length)

        try await withThrowingTaskGroup(of: Int.self) { group in
            for index in ranges.indices.dropFirst(next) {
                group.addTask {
                    try await fetchChunk(index, range: ranges[index], of: job, from: source, progress: progress)
                    return index
                }
            }
            var arrived: Set<Int> = []
            for try await index in group {
                arrived.insert(index)
                while arrived.remove(next) != nil {
                    let chunk = layout.chunkURL(of: file, in: job.artifact, index: next)
                    try part.append(contentsOf: chunk)
                    ModelFiles.remove(chunk)
                    next += 1
                    progress.settle(file.path, bytes: part.length, clearingChunk: next - 1)
                }
            }
        }

        guard try part.finish() == file.sha256, part.length == file.size else { throw SourceProblem.checksumMismatch }
        try ModelFiles.move(partURL, to: layout.url(of: file, in: job.artifact))
    }

    private func fetchChunk(
        _ index: Int, range: Range<Int64>, of job: ModelFileJob, from source: ModelFileSource,
        progress: ModelDownloadProgress
    ) async throws {
        let destination = layout.chunkURL(of: job.file, in: job.artifact, index: index)
        let path = job.file.path
        // It may have arrived in an earlier run of the app.
        if ModelFiles.size(of: destination) == Int64(range.count) {
            progress.arrived(path, chunk: index, bytes: Int64(range.count))
            return
        }
        let request = ModelChunkRequest(url: source.url, range: range, token: source.token, destination: destination)
        try await slots.withSlot {
            var waits = 0
            while true {
                let outcome: ModelChunkOutcome
                do {
                    outcome = try await transport.fetch(request) { progress.arrived(path, chunk: index, bytes: $0) }
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    try Task.checkCancellation()
                    throw SourceProblem.unreachable
                }
                switch outcome {
                case .finished:
                    progress.arrived(path, chunk: index, bytes: Int64(range.count))
                    return
                case .refused(let status, let retryAfter):
                    progress.arrived(path, chunk: index, bytes: 0)
                    let asksToWait = status == 429 || (status == 503 && retryAfter != nil)
                    guard asksToWait, waits < retryPolicy.waits else { throw SourceProblem.refused(status: status) }
                    waits += 1
                    try await sleep(min(retryAfter ?? retryPolicy.defaultWait, retryPolicy.longestWait))
                }
            }
        }
    }
}

/// Bounds how many pieces of work run at once, first come first served: the ranges in
/// flight, and (with one slot) the installer's heavy steps.
actor ModelWorkSlots {
    private var free: Int
    private var waiting: [(id: UInt64, continuation: CheckedContinuation<Void, any Error>)] = []
    private var nextID: UInt64 = 0

    init(_ count: Int) {
        free = max(1, count)
    }

    func withSlot<Result: Sendable>(_ body: @Sendable () async throws -> Result) async throws -> Result {
        try await acquire()
        defer { release() }
        // Work that was cancelled while it waited gives its slot straight back.
        try Task.checkCancellation()
        return try await body()
    }

    private func acquire() async throws {
        try Task.checkCancellation()
        if free > 0 {
            free -= 1
            return
        }
        let id = nextID
        nextID += 1
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                waiting.append((id, continuation))
            }
        } onCancel: {
            Task { await self.abandon(id) }
        }
    }

    private func abandon(_ id: UInt64) {
        guard let index = waiting.firstIndex(where: { $0.id == id }) else { return }
        waiting.remove(at: index).continuation.resume(throwing: CancellationError())
    }

    private func release() {
        if waiting.isEmpty {
            free += 1
        } else {
            // The slot goes straight to the one that waited longest.
            waiting.removeFirst().continuation.resume()
        }
    }
}

/// How much of one artifact's download is on disk or on its way, reported a few times a
/// second at most.
final class ModelDownloadProgress: Sendable {
    private struct State {
        /// Bytes appended to each file's part, or the whole file once it is in place.
        var settled: [String: Int64] = [:]
        /// Bytes of ranges that have arrived or are arriving and are not appended yet.
        var chunks: [String: [Int: Int64]] = [:]
        var lastReport: ContinuousClock.Instant?
        var sequence = 0
    }

    private let state = Mutex(State())
    private let interval: Duration
    /// Called with a number that only grows and the bytes so far.
    private let report: @Sendable (_ sequence: Int, _ bytes: Int64) -> Void

    init(interval: Duration = .milliseconds(250), report: @escaping @Sendable (Int, Int64) -> Void) {
        self.interval = interval
        self.report = report
    }

    /// `bytes` of `file` are in its part file (or the file is whole).
    func settle(_ file: String, bytes: Int64, clearingChunk chunk: Int? = nil) {
        update(always: true) { state in
            state.settled[file] = bytes
            if let chunk { state.chunks[file]?[chunk] = nil }
            if bytes == 0 { state.chunks[file] = nil }
        }
    }

    /// `bytes` of one range of `file` have arrived.
    func arrived(_ file: String, chunk: Int, bytes: Int64) {
        update(always: false) { $0.chunks[file, default: [:]][chunk] = bytes }
    }

    private func update(always: Bool, _ change: (inout State) -> Void) {
        let due: (Int, Int64)? = state.withLock { state in
            change(&state)
            let now = ContinuousClock.now
            if !always, let last = state.lastReport, now - last < interval { return nil }
            state.lastReport = now
            state.sequence += 1
            let bytes = state.settled.values.reduce(0, +) + state.chunks.values.reduce(0) { $0 + $1.values.reduce(0, +) }
            return (state.sequence, bytes)
        }
        if let due { report(due.0, due.1) }
    }
}
