#if DEBUG || HARNESS
import EhDatabase
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
/// - Signed in, a favourite added, moved or removed is accepted, and the site remembers it.
/// - Signed in, the page of a gallery whose favourite was changed, made from its stored page
///   with the favourite as it now is, so the page and the reader's closing page show the
///   change (`PartHarnessGalleryPage`).
/// - Other gallery pages and everything else: offline, so a gallery shows its stored page.
nonisolated struct PartHarnessTransport: HTTPTransport {
    let account: PartHarnessAccount
    let cookies: CookieStore
    /// The harness's database, which holds the stored pages.
    let database: AppDatabase

    private static let site = PartHarnessSite()

    func send(_ request: URLRequest) async throws -> HTTPResponse {
        let url = request.url ?? GalleryHost.ehentai.url
        if cookies.didLogin, let change = Self.favoriteChange(in: request, url: url) {
            await Self.site.setFavorite(gid: change.gid, folder: change.folder)
        }
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
        case .gallery(let gid):
            guard isSignedIn, let folder = await Self.site.favoriteChange(gid: gid),
                  let stored = await storedPage(gid: gid, folder: folder)
            else { return Answer(body: nil, outcome: "offline") }
            return Answer(body: PartHarnessGalleryPage.html(stored), outcome: "served gallery")
        }
        return Answer(body: await Self.site.body(of: page, url: url), outcome: "served")
    }

    /// The stored page of `gid` with the favourite in `folder` (`nil`: none), or `nil` when no
    /// page is stored.
    private func storedPage(gid: String, folder: Int?) async -> PartHarnessGalleryPage.Stored? {
        guard let detail = try? await database.detail(gid: gid) else { return nil }
        let state = try? await database.state(gid: gid)
        var previews: [Int: URL] = [:]
        for page in (try? await database.pages(gid: gid)) ?? [] {
            previews[page.index] = page.previewURL
        }
        let folderName = folder.map { folder in
            PartHarnessAccount.folders.first { $0.index == folder }?.name ?? "Favorites \(folder)"
        }
        return PartHarnessGalleryPage.Stored(
            detail: detail, tags: state?.tags ?? [], comments: state?.comments ?? [],
            previewURLs: previews, favoriteFolder: folderName
        )
    }

    /// The favourite a request adds or moves (`gallerypopups.php` with `favcat`) or removes
    /// (`favorites.php` with `ddact=delete`), or `nil` for any other request.
    private static func favoriteChange(in request: URLRequest, url: URL) -> (gid: String, folder: Int?)? {
        guard request.httpMethod == "POST", let body = request.httpBody.flatMap({ String(data: $0, encoding: .utf8) })
        else { return nil }
        var form = URLComponents()
        form.percentEncodedQuery = body.replacingOccurrences(of: "+", with: "%20")
        let fields = form.queryItems ?? []
        func field(_ name: String) -> String? { fields.first { $0.name == name }?.value }
        switch url.path {
        case "/gallerypopups.php":
            let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            guard let gid = query.first(where: { $0.name == "gid" })?.value,
                  let folder = field("favcat").flatMap(Int.init)
            else { return nil }
            return (gid, folder)
        case "/favorites.php":
            guard field("ddact") == "delete", let gid = field("modifygids[]") else { return nil }
            return (gid, nil)
        default:
            return nil
        }
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
