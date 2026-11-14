import Dependencies
import EhCore
import EhDatabase
import EhModels
import EhNetworking
import Observation

/// What the galleries of a list do besides opening their page: Read straight from a list, and
/// the favourite actions of the long-press menu and the swipe actions.
///
/// One per list on screen, owned by the view that draws the galleries, shared by every list
/// design. The reader is presented by that view from `readingRequest`.
@Observable
public final class GalleryActionsModel {
    /// The reader to present over the list, as a binding target for `readerCover(item:)`.
    public var readingRequest: ReadingRequest?
    /// The favourites changed from this list, by gid, once the site accepted them. A list
    /// overlays them on its entries' marks (`favoriteFolder(of:)`) until it is reloaded.
    public private(set) var favoriteChanges: [String: FavoriteChange] = [:]
    /// The last favourite made here, for the HUD that names its folder and for the tip about
    /// the folder menu.
    public private(set) var favoriteReport: FavoriteReport?
    /// The last operation's result, for the view's haptic.
    public private(set) var feedback: OperationFeedback?

    /// The last history write and the last favourite request, kept so tests can wait for them.
    @ObservationIgnored private(set) var recording: Task<Void, Never>?
    @ObservationIgnored private(set) var lastOperation: Task<Void, Never>?
    @ObservationIgnored let tasks = ModelTasks()
    @ObservationIgnored private var feedbackCounter = FeedbackCounter()
    @ObservationIgnored private var reportCounter = FavoriteReport.Counter()

    @ObservationIgnored @Dependency(\.ehClient) private var client
    @ObservationIgnored @Dependency(\.database) private var database
    @ObservationIgnored @Dependency(\.settings) private var settings
    @ObservationIgnored @Dependency(\.cookieStore) private var cookieStore

    public init() {}

    /// Favourites are offered to a signed-in user only.
    public var isLoggedIn: Bool { cookieStore.didLogin }

    /// The folder holding `entry`'s gallery: a change made here, else the mark its page came
    /// with; `nil` when it is not a favourite.
    public func favoriteFolder(of entry: GalleryEntry) -> Int? {
        switch favoriteChanges[entry.id] {
        case .added(let folder): folder
        case .removed: nil
        case nil: entry.favorite?.folder
        }
    }

    // MARK: Read

    /// Opens the reader at the stored reading progress. The gallery is recorded as opened, as
    /// its page records it, so History lists what was read from a list too.
    public func read(_ gallery: Gallery) {
        readingRequest = ReadingRequest(gallery: gallery)
        // Not tied to the list: the write is short and should land even if the list goes away.
        recording = Task { [database] in
            try? await database.recordOpened(gallery)
        }
    }

    // MARK: Favourites

    /// A one-tap Favourite: into the folder used last.
    public func favorite(_ gallery: Gallery) {
        add(gallery, to: settings.lastFavoriteFolder, kind: .quick)
    }

    /// A folder chosen in the folder menu. It becomes the folder a one-tap Favourite uses.
    public func favorite(_ gallery: Gallery, folder: Int) {
        add(gallery, to: folder, kind: .chosen)
    }

    /// Moves a favourite to another folder: the site's add replaces the folder.
    public func move(_ gallery: Gallery, to folder: Int) {
        add(gallery, to: folder, kind: .moved)
    }

    public func unfavorite(_ gallery: Gallery) {
        guard isLoggedIn else { return }
        let client = client
        let gid = gallery.gid
        perform(gid) {
            try await client.removeFavorite(gid: gid)
        } onSuccess: { model in
            model.favoriteChanges[gid] = .removed
        }
    }

    private func add(_ gallery: Gallery, to folder: Int, kind: FavoriteReport.Kind) {
        guard isLoggedIn, FavoriteReport.folders.contains(folder) else { return }
        let client = client
        let gid = gallery.gid
        let token = gallery.token
        perform(gid) {
            try await client.addFavorite(gid: gid, token: token, category: folder)
        } onSuccess: { model in
            model.favoriteChanges[gid] = .added(folder: folder)
            if kind == .chosen, model.settings.lastFavoriteFolder != folder {
                model.settings.lastFavoriteFolder = folder
            }
            model.favoriteReport = model.reportCounter.next(gid: gid, folder: folder, kind: kind)
        }
    }

    /// Runs one request per gallery (a newer one for the same gallery replaces it). Success
    /// applies `onSuccess` and a success haptic; failure only an error haptic, so nothing that
    /// was shown or stored changes; cancellation nothing.
    private func perform(
        _ gid: String, _ operation: @escaping @Sendable () async throws -> Void,
        onSuccess: @escaping (GalleryActionsModel) -> Void
    ) {
        lastOperation = tasks.run("favorite-\(gid)") { [weak self] in
            let outcome = await Outcome.of(operation)
            guard let self else { return }
            switch outcome {
            case .success:
                onSuccess(self)
                feedback = feedbackCounter.next(.success)
            case .failure:
                feedback = feedbackCounter.next(.failure)
            case .cancelled:
                break
            }
        }
    }
}

/// A favourite changed from a list.
nonisolated public enum FavoriteChange: Equatable, Sendable {
    case added(folder: Int)
    case removed
}

/// A favourite that was made, reported by `GalleryActionsModel` and `GalleryDetailModel` once
/// the site accepted it: the HUD names its folder, and the first quick one is the event the
/// Favourite tip waits for.
nonisolated public struct FavoriteReport: Equatable, Sendable, Identifiable {
    /// The site's ten folders.
    public static let folders = 0...9

    public enum Kind: Equatable, Sendable {
        /// A one-tap Favourite into the folder used last.
        case quick
        /// A folder chosen in the folder menu.
        case chosen
        /// A favourite moved to another folder.
        case moved
    }

    /// Increases with every report of one model, so two equal favourites are two reports.
    public let id: Int
    public let gid: String
    public let folder: Int
    public let kind: Kind

    public var isQuick: Bool { kind == .quick }

    public init(id: Int, gid: String, folder: Int, kind: Kind) {
        self.id = id
        self.gid = gid
        self.folder = folder
        self.kind = kind
    }

    struct Counter {
        private var count = 0

        mutating func next(gid: String, folder: Int, kind: Kind) -> FavoriteReport {
            count += 1
            return FavoriteReport(id: count, gid: gid, folder: folder, kind: kind)
        }
    }
}
