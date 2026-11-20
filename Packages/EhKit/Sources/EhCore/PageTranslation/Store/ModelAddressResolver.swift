import Foundation
import Synchronization

/// Finds the address a request with a token is handed to a background session with.
///
/// A background session follows redirects by itself and drops `Authorization` on every
/// one, also when a store points to another path of its own host: Hugging Face answers a
/// small file with a 307 to `/api/resolve-cache/…` on huggingface.co, where a private
/// repository still wants the token. So the first hops are taken here, by a session that
/// asks before it follows. As long as an address redirects to its own host, the token goes
/// along; the first address that answers, or that points to another host, is the one the
/// background session gets. From there the system follows on its own and the token stops,
/// which is right for a signed address on another host.
///
/// One question a file, a byte long, remembered for as long as the app runs.
final class ModelAddressResolver: Sendable {
    /// A store that keeps pointing at itself is not followed for ever.
    static let longestChain = 5

    private let session: URLSession
    private let resolving = Mutex<[URL: Task<URL?, Never>]>([:])

    init(configuration: URLSessionConfiguration) {
        session = URLSession(configuration: configuration, delegate: RedirectRefuser(), delegateQueue: nil)
    }

    deinit {
        session.finishTasksAndInvalidate()
    }

    /// The address to ask for the file at `url`. When the store cannot be reached now, that
    /// is `url` itself, and the question is asked again the next time.
    func address(for url: URL, token: String?) async -> URL {
        let task = resolving.withLock { resolving -> Task<URL?, Never> in
            if let task = resolving[url] { return task }
            let task = Task { [session] in await Self.follow(url, token: token, with: session) }
            resolving[url] = task
            return task
        }
        if let address = await task.value { return address }
        resolving.withLock { resolving in
            if resolving[url] == task { resolving[url] = nil }
        }
        return url
    }

    /// Follows `url` while it redirects to its own host. `nil` when a request failed.
    private static func follow(_ url: URL, token: String?, with session: URLSession) async -> URL? {
        var current = url
        for _ in 0..<longestChain {
            // One byte: enough to see where the address leads, whatever the file's size.
            let request = ModelChunkDelivery.urlRequest(url: current, range: 0..<1, token: token)
            guard let (bytes, response) = try? await session.bytes(for: request) else { return nil }
            // The answer's headers are all that is wanted. A source that ignores `Range`
            // would go on to send the whole file.
            bytes.task.cancel()
            guard let next = ModelChunkDelivery.sameHostRedirect(in: response, from: current, startedAt: url)
            else { return current }
            current = next
        }
        return current
    }
}

/// Refuses every redirect, so the answer that redirects is the answer the caller sees.
private final class RedirectRefuser: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}
