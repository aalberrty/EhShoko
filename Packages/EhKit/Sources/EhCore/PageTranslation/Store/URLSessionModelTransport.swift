import Foundation
import Synchronization

/// The app's model transport: download tasks of one `URLSession`, each with a `Range`.
///
/// In the app the session is a background one. Checked on the iOS 18.2 and 26.3 simulators:
/// a background download task sends its `Range` header as given, also through a redirect;
/// the system drops `Authorization` on every redirect; and tasks handed over before the app
/// is killed finish without it, after which the system starts the app again to deliver
/// them. So every range of a download is handed to the system at once and goes on while the
/// app is suspended or gone.
public final class URLSessionModelTransport: ModelTransport {
    private let session: URLSession
    private let handler: Handler
    private let identifier: String?

    /// - Parameters:
    ///   - identifier: the background session's name, or `nil` for a session that is not one.
    ///   - root: the model store's folder; destinations are remembered relative to it.
    public init(configuration: URLSessionConfiguration, identifier: String?, root: URL) {
        let handler = Handler(root: root)
        self.handler = handler
        self.identifier = identifier
        session = URLSession(configuration: configuration, delegate: handler, delegateQueue: nil)
    }

    deinit {
        // A session keeps its delegate until it is told it is no longer needed.
        session.finishTasksAndInvalidate()
    }

    /// The transport of the app: a background session that sends no cookie, keeps no cache
    /// and wakes the app when its transfers are done.
    public static func background(identifier: String, root: URL) -> URLSessionModelTransport {
        let configuration = URLSessionConfiguration.background(withIdentifier: identifier)
        configuration.sessionSendsLaunchEvents = true
        configuration.isDiscretionary = false
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.httpMaximumConnectionsPerHost = 4
        // A transfer that waits for a network gives up after a day and is asked for again.
        configuration.timeoutIntervalForResource = 24 * 60 * 60
        return URLSessionModelTransport(configuration: configuration, identifier: identifier, root: root)
    }

    public func fetch(
        _ request: ModelChunkRequest, received: @escaping @Sendable (Int64) -> Void
    ) async throws -> ModelChunkOutcome {
        guard let ticket = ModelChunkTicket(request, root: handler.root) else {
            throw ModelTransportFailure.destinationOutsideStore
        }
        await collectEarlierTransfers()
        try Task.checkCancellation()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                switch handler.register(ticket, request: request, received: received, continuation, in: session) {
                case .delivered: continuation.resume(returning: .finished)
                case .alreadyAwaited: continuation.resume(throwing: ModelTransportFailure.rangeAlreadyAwaited)
                case .joined: break
                case .started(let task): task.resume()
                }
                // The task may have been cancelled before there was anything to stop.
                if Task.isCancelled { handler.cancel(ticket) }
            }
        } onCancel: {
            handler.cancel(ticket)
        }
    }

    public func collectEarlierTransfers() async {
        await handler.attach(to: session)
    }

    public func handleBackgroundEvents(identifier: String, delivered: @escaping @Sendable () -> Void) -> Bool {
        guard let own = self.identifier, own == identifier else { return false }
        handler.state.withLock { $0.eventsDelivered = delivered }
        return true
    }
}

public enum ModelTransportFailure: Error, Equatable {
    /// A range's destination must be inside the model store's folder.
    case destinationOutsideStore
    /// The same range was asked for twice at once.
    case rangeAlreadyAwaited
}

// MARK: The session's delegate

private final class Handler: NSObject, URLSessionDownloadDelegate, Sendable {
    let root: URL
    let state = TransferState()

    init(root: URL) {
        self.root = root
    }

    enum Registration: Sendable {
        case delivered, alreadyAwaited, joined
        case started(URLSessionDownloadTask)
    }

    func register(
        _ ticket: ModelChunkTicket, request: ModelChunkRequest, received: @escaping @Sendable (Int64) -> Void,
        _ continuation: CheckedContinuation<ModelChunkOutcome, any Error>, in session: URLSession
    ) -> Registration {
        state.withLock { state -> Registration in
            // A finished task leaves `tasks` only after its file is in place, so a range
            // that is neither on disk nor in `tasks` here is not under way anywhere.
            if ticket.isDelivered(in: root) { return .delivered }
            guard state.waiters[ticket] == nil else { return .alreadyAwaited }
            state.waiters[ticket] = Waiter(continuation: continuation, received: received)
            if state.tasks[ticket] != nil { return .joined }
            let task = session.downloadTask(with: ModelChunkDelivery.urlRequest(for: request))
            task.taskDescription = ticket.description
            state.tasks[ticket] = task
            return .started(task)
        }
    }

    func cancel(_ ticket: ModelChunkTicket) {
        state.withLock { $0.tasks[ticket] }?.cancel()
    }

    /// Learns which transfers of an earlier run are still under way. Once per process.
    func attach(to session: URLSession) async {
        let attaching = state.withLock { state -> Task<Void, Never> in
            if let attaching = state.attaching { return attaching }
            let attaching = Task { [state = self.state] in
                for task in await session.allTasks {
                    guard let ticket = ModelChunkTicket(description: task.taskDescription) else { continue }
                    state.withLock { state in
                        // A task that ended while the list was on its way is not under way.
                        guard state.tasks[ticket] == nil, !state.ended.contains(task.taskIdentifier) else { return }
                        state.tasks[ticket] = task
                    }
                }
            }
            state.attaching = attaching
            return attaching
        }
        await attaching.value
    }

    // MARK: URLSessionDownloadDelegate

    func urlSession(
        _ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL
    ) {
        guard let ticket = ModelChunkTicket(description: downloadTask.taskDescription) else { return }
        // The file at `location` is gone when this returns, so it is moved here.
        let outcome = ModelChunkDelivery.deliver(location, response: downloadTask.response, ticket: ticket, root: root)
        state.withLock { $0.outcomes[downloadTask.taskIdentifier] = outcome }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        guard let ticket = ModelChunkTicket(description: task.taskDescription) else { return }
        let (waiter, outcome) = state.withLock { state -> (Waiter?, ModelChunkOutcome?) in
            state.ended.insert(task.taskIdentifier)
            let outcome = state.outcomes.removeValue(forKey: task.taskIdentifier)
            // Only the task that is on record for the range ends the wait for it.
            if let current = state.tasks[ticket], current.taskIdentifier != task.taskIdentifier {
                return (nil, outcome)
            }
            state.tasks[ticket] = nil
            return (state.waiters.removeValue(forKey: ticket), outcome)
        }
        guard let waiter else { return }
        if let error {
            let cancelled = (error as? URLError)?.code == .cancelled
            waiter.continuation.resume(throwing: cancelled ? CancellationError() : error)
        } else {
            waiter.continuation.resume(returning: outcome ?? .refused(status: 0, retryAfter: nil))
        }
    }

    func urlSession(
        _ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64
    ) {
        guard let ticket = ModelChunkTicket(description: downloadTask.taskDescription) else { return }
        state.withLock { $0.waiters[ticket]?.received }?(totalBytesWritten)
    }

    /// Only a session that is not a background one asks. The system has already taken the
    /// token off the new request; this makes sure of it for any other host.
    func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(ModelChunkDelivery.redirected(request, from: task.originalRequest?.url))
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        let delivered = state.withLock { state in
            defer { state.eventsDelivered = nil }
            return state.eventsDelivered
        }
        delivered?()
    }
}

private struct Waiter: Sendable {
    let continuation: CheckedContinuation<ModelChunkOutcome, any Error>
    let received: @Sendable (Int64) -> Void
}

/// What the delegate and the callers share. A class of its own because the delegate is an
/// Objective-C object.
private final class TransferState: Sendable {
    struct Value {
        /// Transfers the system has, by what they fetch.
        var tasks: [ModelChunkTicket: URLSessionTask] = [:]
        var waiters: [ModelChunkTicket: Waiter] = [:]
        /// How a finished task's file was dealt with, until the task reports its end.
        var outcomes: [Int: ModelChunkOutcome] = [:]
        /// The identifiers of tasks that have reported their end.
        var ended: Set<Int> = []
        var attaching: Task<Void, Never>?
        var eventsDelivered: (@Sendable () -> Void)?
    }

    private let value = Mutex(Value())

    func withLock<Result: Sendable>(_ body: (inout Value) -> Result) -> Result {
        value.withLock { body(&$0) }
    }
}

// MARK: Judging an answer

/// What to make of a finished download task: pure, so the rules are tested on the host.
enum ModelChunkDelivery {
    /// The request for one range: the range, the token for this address, and nothing else
    /// about the app or the user.
    static func urlRequest(for request: ModelChunkRequest) -> URLRequest {
        var urlRequest = URLRequest(url: request.url, cachePolicy: .reloadIgnoringLocalCacheData)
        urlRequest.httpShouldHandleCookies = false
        urlRequest.setValue(
            "bytes=\(request.range.lowerBound)-\(request.range.upperBound - 1)", forHTTPHeaderField: "Range"
        )
        // Compressed bytes would not be the range that was asked for.
        urlRequest.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        // The default names the app to every host; the hosts need to know nothing.
        urlRequest.setValue("ModelStore/1", forHTTPHeaderField: "User-Agent")
        if let token = request.token, !token.isEmpty {
            urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return urlRequest
    }

    /// Moves the downloaded file into place when it is the range that was asked for.
    static func deliver(
        _ location: URL, response: URLResponse?, ticket: ModelChunkTicket, root: URL
    ) -> ModelChunkOutcome {
        guard let response = response as? HTTPURLResponse else { return .refused(status: 0, retryAfter: nil) }
        let outcome = judge(
            status: response.statusCode, contentRange: response.value(forHTTPHeaderField: "Content-Range"),
            retryAfter: response.value(forHTTPHeaderField: "Retry-After"), length: ModelFiles.size(of: location),
            ticket: ticket
        )
        guard outcome == .finished else { return outcome }
        do {
            try ModelFiles.move(location, to: ticket.destination(in: root))
            return .finished
        } catch {
            return .refused(status: 0, retryAfter: nil)
        }
    }

    static func judge(
        status: Int, contentRange: String?, retryAfter: String?, length: Int64?, ticket: ModelChunkTicket
    ) -> ModelChunkOutcome {
        let refused = ModelChunkOutcome.refused(status: status, retryAfter: delay(fromRetryAfter: retryAfter))
        guard length == ticket.count else { return refused }
        switch status {
        case 206:
            // A range that starts elsewhere is not ours, whatever its length.
            if let first = firstByte(ofContentRange: contentRange), first != ticket.first { return refused }
            return .finished
        case 200:
            // A source that ignores `Range` sends the whole file, which is the range only
            // when the range is the whole file.
            return ticket.first == 0 ? .finished : refused
        default:
            return refused
        }
    }

    /// `bytes 100-199/1000` → 100.
    static func firstByte(ofContentRange value: String?) -> Int64? {
        guard let value, let unitEnd = value.firstIndex(of: " "), let dash = value.firstIndex(of: "-"),
              unitEnd < dash
        else { return nil }
        return Int64(value[value.index(after: unitEnd)..<dash].trimmingCharacters(in: .whitespaces))
    }

    /// `Retry-After` as seconds or as an HTTP date.
    static func delay(fromRetryAfter value: String?, now: Date = Date()) -> Duration? {
        guard let value = value?.trimmingCharacters(in: .whitespaces), !value.isEmpty else { return nil }
        if let seconds = Double(value) { return .seconds(max(0, seconds)) }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        guard let date = formatter.date(from: value) else { return nil }
        return .seconds(max(0, date.timeIntervalSince(now)))
    }

    /// The request to follow a redirect with: without the token unless it stays on the host
    /// the token was meant for.
    static func redirected(_ request: URLRequest, from original: URL?) -> URLRequest {
        var request = request
        if !isSameOrigin(request.url, original) {
            request.setValue(nil, forHTTPHeaderField: "Authorization")
        }
        return request
    }

    static func isSameOrigin(_ url: URL?, _ other: URL?) -> Bool {
        guard let url, let other, let host = url.host(), let otherHost = other.host() else { return false }
        return host.lowercased() == otherHost.lowercased() && url.scheme?.lowercased() == other.scheme?.lowercased()
            && port(of: url) == port(of: other)
    }

    private static func port(of url: URL) -> Int {
        url.port ?? (url.scheme?.lowercased() == "http" ? 80 : 443)
    }
}
