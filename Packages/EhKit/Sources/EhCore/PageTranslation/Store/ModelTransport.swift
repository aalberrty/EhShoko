import Foundation

/// One range of one model file, asked of one source.
public struct ModelChunkRequest: Sendable, Hashable {
    /// The file's address at the source.
    public var url: URL
    /// The bytes asked for, as offsets into the file.
    public var range: Range<Int64>
    /// Sent as `Authorization: Bearer` to `url`'s host, also when that host redirects to
    /// another path of itself, and never to another host it redirects to.
    public var token: String?
    /// Where the bytes are put: a file inside the model store's folder. It exists, with
    /// exactly `range.count` bytes, only once the whole range has arrived.
    public var destination: URL

    public init(url: URL, range: Range<Int64>, token: String?, destination: URL) {
        self.url = url
        self.range = range
        self.token = token
        self.destination = destination
    }
}

/// How a chunk request ended, when the source answered at all.
public enum ModelChunkOutcome: Sendable, Equatable {
    /// `destination` holds the range.
    case finished
    /// The source answered with something other than the range: a 403, 404, 429 or 5xx, or
    /// a body of the wrong length. `retryAfter` is what a 429 or 503 asked for.
    case refused(status: Int, retryAfter: Duration?)
}

/// Moves the bytes of model files. The model store's one way to the network: it sends no
/// cookie and nothing about the user, and tests replace it the way site tests replace the
/// HTTP transport.
///
/// A transfer may outlive the process (the app's transport is a background `URLSession`).
/// A request is named by its destination and range, so asking again for a range that is
/// still under way, or that arrived while the app was not running, joins or returns that
/// transfer rather than starting another.
public protocol ModelTransport: Sendable {
    /// Fetches one range into `request.destination`. `received` reports how many bytes of
    /// the range have arrived so far, from any thread. Cancelling the calling task stops
    /// the transfer; a connection that fails throws.
    func fetch(
        _ request: ModelChunkRequest, received: @escaping @Sendable (Int64) -> Void
    ) async throws -> ModelChunkOutcome

    /// Takes delivery of what transfers begun in an earlier run of the app left behind, so
    /// their ranges are in place before anything is asked for again.
    func collectEarlierTransfers() async

    /// The system woke the app for the background session `identifier`. Returns whether
    /// that session is this transport's; if so `delivered` is called once every waiting
    /// event has been handled.
    func handleBackgroundEvents(identifier: String, delivered: @escaping @Sendable () -> Void) -> Bool
}

extension ModelTransport {
    public func collectEarlierTransfers() async {}

    public func handleBackgroundEvents(identifier: String, delivered: @escaping @Sendable () -> Void) -> Bool {
        false
    }
}
