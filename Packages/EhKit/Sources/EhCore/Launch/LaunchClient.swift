import Dependencies
import EhDatabase
import EhNetworking
import Foundation

/// The launch work that touches disk, as replaceable steps. `AppModel` decides the order.
public struct LaunchClient: Sendable {
    /// Cookie housekeeping (legacy `AppDelegateReducer.onLaunchFinish`). Runs off the main actor.
    public var prepareCookies: @Sendable () async -> Void
    /// Opens, creating or migrating it if needed, the app database.
    public var openDatabase: @Sendable () async throws -> AppDatabase
    /// Deletes the database files so the next open starts empty ("Drop the database").
    public var dropDatabase: @Sendable () async throws -> Void
    /// Makes the database available to everything that reads `\.database`.
    public var installDatabase: @Sendable (AppDatabase) -> Void
    /// Deletes the stored page URLs of galleries not opened within `pageLifetime`; the site's
    /// image URLs expire (legacy `removeExpiredImageURLs`).
    public var expirePages: @Sendable (AppDatabase) async throws -> Void

    /// Legacy kept page URLs for a week after a gallery was last opened.
    public static let pageLifetime: TimeInterval = 7 * 24 * 60 * 60

    public init(
        prepareCookies: @escaping @Sendable () async -> Void,
        openDatabase: @escaping @Sendable () async throws -> AppDatabase,
        dropDatabase: @escaping @Sendable () async throws -> Void,
        installDatabase: @escaping @Sendable (AppDatabase) -> Void,
        expirePages: @escaping @Sendable (AppDatabase) async throws -> Void
    ) {
        self.prepareCookies = prepareCookies
        self.openDatabase = openDatabase
        self.dropDatabase = dropDatabase
        self.installDatabase = installDatabase
        self.expirePages = expirePages
    }
}

extension LaunchClient: DependencyKey {
    public static let liveValue = LaunchClient(
        prepareCookies: {
            @Dependency(\.cookieStore) var cookies
            await CookieHousekeeping.run(cookies)
        },
        openDatabase: { try await AppDatabase.open(at: LiveDatabase.defaultURL) },
        dropDatabase: { try await DatabaseFiles.delete(at: LiveDatabase.defaultURL) },
        installDatabase: { LiveDatabase.install($0) },
        expirePages: { try await $0.deleteExpiredPages(notOpenedWithin: pageLifetime) }
    )

    public static let testValue = LaunchClient(
        prepareCookies: unimplemented("LaunchClient.prepareCookies"),
        openDatabase: unimplemented("LaunchClient.openDatabase"),
        dropDatabase: unimplemented("LaunchClient.dropDatabase"),
        installDatabase: unimplemented("LaunchClient.installDatabase"),
        expirePages: unimplemented("LaunchClient.expirePages")
    )

    /// An in-memory database.
    public static let previewValue = LaunchClient(
        prepareCookies: {},
        openDatabase: { try await AppDatabase.inMemory() },
        dropDatabase: {},
        installDatabase: { _ in },
        expirePages: { _ in }
    )
}

extension DependencyValues {
    public var launchClient: LaunchClient {
        get { self[LaunchClient.self] }
        set { self[LaunchClient.self] = newValue }
    }
}

/// Cookie fixes applied on every launch.
enum CookieHousekeeping {
    /// Legacy ran these in the order remove `yay`, sync ExHentai cookies, ignore offensive,
    /// fill the other host. Filling the other host first means credentials copied from
    /// e-hentai.org reach s.exhentai.org in the same launch instead of the next one.
    @concurrent
    static func run(_ cookies: CookieStore) async {
        cookies.removeYay()
        cookies.fulfillAnotherHostField()
        cookies.syncExCookies()
        cookies.ignoreOffensive()
    }
}

/// The SQLite files of a database.
enum DatabaseFiles {
    /// Deletes the database and its `-wal` and `-shm` files. Files already gone are ignored.
    @concurrent
    static func delete(at url: URL) async throws {
        for suffix in ["", "-wal", "-shm"] {
            do {
                try FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + suffix))
            } catch CocoaError.fileNoSuchFile {
                continue
            }
        }
    }
}
