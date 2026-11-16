#if DEBUG || HARNESS
import EhModels
import EhNetworking
import Foundation
import Synchronization

/// The part harness's network: it records every request and answers from the harness's site
/// (`PartHarnessSite`) what the account's mode serves, and nothing leaves the device.
///
/// - Signed in, every favourites page; with `-HarnessNetwork`, every list as well.
/// - Signed out, with `-HarnessNetwork`, the lists that need no account, and the site's login
///   prompt for those that do; without it, nothing.
/// - Signed in, a favourite added, moved or removed is accepted.
/// - Gallery pages and everything else: offline, so a gallery shows its stored page.
nonisolated struct PartHarnessTransport: HTTPTransport {
    let account: PartHarnessAccount
    let cookies: CookieStore

    private static let site = PartHarnessSite()

    func send(_ request: URLRequest) async throws -> HTTPResponse {
        let url = request.url ?? GalleryHost.ehentai.url
        let answer = await answer(to: url)
        PartHarnessRequestLog.append(method: request.httpMethod ?? "GET", url: url, outcome: answer.outcome)
        if account.latency > 0 {
            try await Task.sleep(for: .seconds(account.latency))
        }
        guard let body = answer.body else { throw URLError(.notConnectedToInternet) }
        let response = HTTPURLResponse(
            url: url, statusCode: 200, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "text/html; charset=UTF-8"]
        ) ?? HTTPURLResponse()
        return HTTPResponse(data: Data(body.utf8), response: response)
    }

    private struct Answer {
        let body: String?
        let outcome: String
    }

    private func answer(to url: URL) async -> Answer {
        // Favourites added, moved or removed while signed in: accepted (the client reads no
        // body), so a one-tap Favourite earns the Favourite tip here as on the site.
        if url.path == "/gallerypopups.php", cookies.didLogin {
            return Answer(body: "<html></html>", outcome: "accepted")
        }
        guard let page = PartHarnessSite.Page(url: url) else { return Answer(body: nil, outcome: "offline") }
        let isSignedIn = cookies.didLogin
        switch page {
        case .favorites:
            guard account.loadsLists || isSignedIn else { return Answer(body: nil, outcome: "offline") }
            guard isSignedIn else { return Answer(body: PartHarnessSite.loginPrompt, outcome: "login") }
            if let file = Self.fixtureFile(for: url), let body = try? String(contentsOfFile: file, encoding: .utf8) {
                return Answer(body: body, outcome: "served \((file as NSString).lastPathComponent)")
            }
        case .watched:
            guard account.loadsLists else { return Answer(body: nil, outcome: "offline") }
            guard isSignedIn else { return Answer(body: PartHarnessSite.loginPrompt, outcome: "login") }
        case .list:
            guard account.loadsLists else { return Answer(body: nil, outcome: "offline") }
        }
        return Answer(body: await Self.site.body(of: page, url: url), outcome: "served")
    }

    /// `-HarnessFixturePath<folder>`, else `-HarnessFixturePath`, for a favourites URL.
    private static func fixtureFile(for url: URL) -> String? {
        let folder = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "favcat" }?.value ?? ""
        let defaults = UserDefaults.standard
        return defaults.string(forKey: "HarnessFixturePath\(folder)") ?? defaults.string(forKey: "HarnessFixturePath")
    }
}

/// `Documents/harness-requests.txt`: one line per request, in the order they were sent.
nonisolated enum PartHarnessRequestLog {
    private static let lock = Mutex(())

    static var fileURL: URL {
        URL.documentsDirectory.appending(path: "harness-requests.txt")
    }

    /// Starts an empty log, so a file left by an earlier launch does not pass for this one's.
    static func reset() {
        lock.withLock { _ in
            try? Data().write(to: fileURL, options: .atomic)
        }
    }

    static func append(method: String, url: URL, outcome: String) {
        let time = String(format: "%.3f", Date().timeIntervalSince1970)
        let line = "\(time) \(method) \(url.absoluteString) \(outcome)\n"
        lock.withLock { _ in
            guard let handle = try? FileHandle(forWritingTo: fileURL) else {
                try? Data(line.utf8).write(to: fileURL, options: .atomic)
                return
            }
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(line.utf8))
        }
    }
}
#endif
