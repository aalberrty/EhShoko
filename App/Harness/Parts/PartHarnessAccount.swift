#if DEBUG || HARNESS
import Dependencies
import EhCore
import EhFeatures
import EhModels
import EhNetworking
import Foundation
import Synchronization

/// The account of a part harness launched as the whole app (`-Harness part`): a cookie jar, a
/// user store and a client of its own, so that signing in, the folders' names and every request
/// stay inside the harness. The user's cookie jar, profile and settings are never read or
/// written, and the database is the harness's own (`PartHarnessDependencies`).
///
/// | Argument | Meaning |
/// |---|---|
/// | `-HarnessSignedIn YES` | Signed in: login cookies in the harness's jar, and ten named folders with their counts in its user store, 1,284 galleries in all. Lists stay fixtures; favourites pages come from the client (`PartHarnessTransport`), so a library that loads its own (Wall's piles) has them. |
/// | `-HarnessNetwork YES` | Every list loads through the client from the harness's site (`PartHarnessSite`) instead of the fixtures. Signed in, but without the folders: their names and counts arrive with the first favourites page, as on the site. `-HarnessLibraryNetwork YES` is the same. |
/// | `-HarnessSignInAfter <s>` | Starts signed out and signs in after s seconds. |
/// | `-HarnessLatency <s>` | How long the client takes to answer, 0.3 s by default. |
/// | `-HarnessFixturePath <file>`, `-HarnessFixturePath<n> <file>` | A favourites page from a file on the Mac, which a simulator can read, for every folder or for folder n (`all` for All), instead of the generated one. |
///
/// Every request the client is asked for is written to `Documents/harness-requests.txt`, one
/// line each: the time, the method, the URL and what the harness answered (`served`,
/// `login`, `offline`). Signed out and without `-HarnessNetwork` the client answers nothing,
/// as the offline client it replaces did.
nonisolated struct PartHarnessAccount: Sendable {
    var isSignedIn = false
    var loadsLists = false
    var signInAfter: Double?
    var latency = 0.3

    static let atLaunch: PartHarnessAccount = {
        let defaults = UserDefaults.standard
        var account = PartHarnessAccount()
        account.isSignedIn = defaults.bool(forKey: "HarnessSignedIn")
        account.loadsLists = defaults.bool(forKey: "HarnessNetwork") || defaults.bool(forKey: "HarnessLibraryNetwork")
        let after = defaults.double(forKey: "HarnessSignInAfter")
        account.signInAfter = after > 0 ? after : nil
        if defaults.object(forKey: "HarnessLatency") != nil {
            account.latency = max(defaults.double(forKey: "HarnessLatency"), 0)
        }
        return account
    }()

    /// Signed in from the start: either flag asks for an account, unless it comes later.
    var startsSignedIn: Bool { (isSignedIn || loadsLists) && signInAfter == nil }

    /// The jar the harness's client, account and lists read. One per process.
    static let cookies = CookieStore(storage: PartHarnessCookieJar())

    /// The ten folders `-HarnessSignedIn` starts with: named, with counts, one of them empty.
    static let folders: [FavoriteFolder] = [
        ("To Read", 42), ("Top Shelf", 118), ("Artists I Follow", 203), ("Full Colour", 76),
        ("Long Series", 31), ("Translated · 中文", 655), ("Art & CG Sets", 97), ("Favorites 7", 22),
        ("Favorites 8", 40), ("Favorites 9", 0),
    ].enumerated().map { FavoriteFolder(index: $0.offset, name: $0.element.0, count: $0.element.1) }

    private static let userSuite = "app.ehshoko.part-harness.user"

    /// Puts the harness's jar, user store and client in place of the app's.
    func install(in values: inout DependencyValues) {
        if startsSignedIn {
            Self.signIn()
        }
        values.cookieStore = Self.cookies
        let defaults = UserDefaults(suiteName: Self.userSuite) ?? .standard
        defaults.removePersistentDomain(forName: Self.userSuite)
        values.userStore = UserStore(defaults: defaults)
        PartHarnessRequestLog.reset()
        values.ehClient = EhClient(
            transport: PartHarnessTransport(account: self, cookies: Self.cookies),
            cookies: Self.cookies, host: { .ehentai }
        )
    }

    /// What the account adds once the harness's stores exist, before anything is shown: the
    /// folders, and the session's look at the jar.
    @MainActor
    func prepare() {
        @Dependency(\.userStore) var userStore
        @Dependency(\.accountSession) var session
        if isSignedIn {
            userStore.updateFavoriteFolders(Self.folders)
        }
        session.cookiesDidChange()
    }

    /// `-HarnessSignInAfter`: waits, then signs in, as a login would.
    @MainActor
    func signInLater() async {
        guard let signInAfter else { return }
        do {
            try await Task.sleep(for: .seconds(signInAfter))
        } catch {
            return
        }
        Self.signIn()
        @Dependency(\.accountSession) var session
        session.cookiesDidChange()
    }

    /// The cookies of a login on e-hentai.org, with a member id nobody has.
    private static func signIn() {
        let url = GalleryHost.ehentai.url
        cookies.setOrEditCookie(for: url, name: CookieName.ipbMemberId, value: "1234567")
        cookies.setOrEditCookie(for: url, name: CookieName.ipbPassHash, value: "0123456789abcdef0123456789abcdef")
    }
}

/// A cookie jar in memory. `HTTPCookieStorage()` silently drops what it is given on Apple
/// platforms and `.shared` is the user's, so the harness keeps its own. It has what
/// `CookieStore` uses, with host and path matching.
///
/// `@unchecked Sendable`: the only state is behind the mutex.
nonisolated final class PartHarnessCookieJar: HTTPCookieStorage, @unchecked Sendable {
    private let storage = Mutex<[HTTPCookie]>([])

    override init() {
        super.init()
    }

    override var cookies: [HTTPCookie]? {
        storage.withLock { $0 }
    }

    override func setCookie(_ cookie: HTTPCookie) {
        storage.withLock { cookies in
            cookies.removeAll { Self.isSame($0, cookie) }
            cookies.append(cookie)
        }
    }

    override func deleteCookie(_ cookie: HTTPCookie) {
        storage.withLock { $0.removeAll { Self.isSame($0, cookie) } }
    }

    override func removeCookies(since date: Date) {
        storage.withLock { $0.removeAll() }
    }

    override func setCookies(_ cookies: [HTTPCookie], for url: URL?, mainDocumentURL: URL?) {
        cookies.forEach(setCookie)
    }

    override func cookies(for url: URL) -> [HTTPCookie]? {
        guard let host = url.host?.lowercased() else { return nil }
        let path = url.path.isEmpty ? "/" : url.path
        return storage.withLock { cookies in
            cookies.filter { cookie in
                let domain = cookie.domain.lowercased()
                let bare = domain.hasPrefix(".") ? String(domain.dropFirst()) : domain
                let hostMatches = host == bare || (domain.hasPrefix(".") && host.hasSuffix(domain))
                return hostMatches && path.hasPrefix(cookie.path)
            }
        }
    }

    private static func isSame(_ lhs: HTTPCookie, _ rhs: HTTPCookie) -> Bool {
        lhs.name == rhs.name && lhs.domain.lowercased() == rhs.domain.lowercased() && lhs.path == rhs.path
    }
}
#endif
