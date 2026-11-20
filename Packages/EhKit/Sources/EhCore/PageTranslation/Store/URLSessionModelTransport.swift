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
///
/// The system drops the token on a redirect to the same host too, and a background session
/// does not ask before it follows one. So a request with a token is first taken past the
/// redirects of its own host by `ModelAddressResolver`, and the background session is given
/// the address that answers.
public final class URLSessionModelTransport: ModelTransport {
    private let session: URLSession
    private let handler: Handler
    private let identifier: String?
    private let resolver: ModelAddressResolver?

    /// - Parameters:
    ///   - identifier: the background session's name, or `nil` for a session that is not one.
    ///   - root: the model store's folder; destinations are remembered relative to it.
    ///   - resolverConfiguration: the session that takes a request with a token past the
    ///     redirects of its own host. A background session needs one; a session that asks
    ///     its delegate about redirects does not.
    public init(
        configuration: URLSessionConfiguration, identifier: String?, root: URL,
        resolverConfiguration: URLSessionConfiguration? = nil
    ) {
        let handler = Handler(root: root)
        self.handler = handler
        self.identifier = identifier
        session = URLSession(configuration: configuration, delegate: handler, delegateQueue: nil)
        resolver = resolverConfiguration.map(ModelAddressResolver.init(configuration:))
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
        let resolving = URLSessionConfiguration.ephemeral
        resolving.httpCookieStorage = nil
        resolving.httpShouldSetCookies = false
        resolving.urlCache = nil
        resolving.timeoutIntervalForRequest = 30
        return URLSessionModelTransport(
            configuration: configuration, identifier: identifier, root: root, resolverConfiguration: resolving
        )
    }

    public func fetch(
        _ request: ModelChunkRequest, received: @escaping @Sendable (Int64) -> Void
    ) async throws -> ModelChunkOutcome {
        guard let ticket = ModelChunkTicket(request, root: handler.root) else {
            throw ModelTransportFailure.destinationOutsideStore
        }
        await collectEarlierTransfers()
        try Task.checkCancellation()
        var request = request
        // Only a range that will really be asked for is worth a question to the store.
        if let resolver, request.token?.isEmpty == false, handler.needsTransfer(ticket) {
            request.url = await resolver.address(for: request.url, token: request.token)
            try Task.checkCancellation()
        }
        return try await withTaskCancellationHandler { [request] in
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

    /// Whether fetching this range would start a transfer: it is neither in place nor
    /// under way.
    func needsTransfer(_ ticket: ModelChunkTicket) -> Bool {
        state.withLock { !ticket.isDelivered(in: root) && $0.tasks[ticket] == nil }
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
    /// token off the new request: it is put back for the host it was meant for, and kept
    /// off for any other.
    func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(ModelChunkDelivery.redirected(request, from: task.originalRequest))
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
