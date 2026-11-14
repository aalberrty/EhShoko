import Dependencies
import EhCore
import EhDatabase
import EhModels
import Observation

/// One gallery in progress, as Continue shows it.
public nonisolated struct ContinueItem: Identifiable, Equatable, Sendable {
    public let gallery: Gallery
    /// The 1-based page last read, between 1 and `pageCount - 1`.
    public let page: Int
    public let pageCount: Int

    public var id: String { gallery.gid }

    /// How far through the gallery the reader is, from 0 to 1.
    public var fraction: Double {
        pageCount > 0 ? Double(page) / Double(pageCount) : 0
    }

    public init(gallery: Gallery, page: Int, pageCount: Int) {
        self.gallery = gallery
        self.page = page
        self.pageCount = pageCount
    }
}

/// The galleries started and not finished, most recently opened first: what the Continue
/// accessory, card, banner and shelf show. One model for every design, owned by the shell.
///
/// **Driving it from a view.** `.task { await model.observe() }` on the shell's root follows
/// the database until the view goes away. Opening a gallery, turning a page and clearing the
/// history all reach it through the database; nothing calls it to refresh.
@Observable
public final class ContinueModel {
    /// Shelf's shelf shows up to ten.
    public static let defaultLimit = 10

    /// At most `limit` galleries in progress, most recently opened first.
    public private(set) var items: [ContinueItem] = []
    /// The most recent of `items`. Stored on its own so a view that shows only this one is not
    /// invalidated when another item changes.
    public private(set) var first: ContinueItem?
    /// `.loading` until the database first answers.
    public private(set) var loadingState: LoadingState = .loading

    @ObservationIgnored private let limit: Int
    @ObservationIgnored @Dependency(\.database) private var database

    public init(limit: Int = ContinueModel.defaultLimit) {
        self.limit = limit
    }

    /// Follows the reading list until the calling task is cancelled.
    public func observe() async {
        do {
            for try await rows in database.observeReadingList(limit: limit) {
                apply(await Self.items(from: rows))
            }
        } catch {
            guard !(error is CancellationError), !Task.isCancelled else { return }
            loadingState = .failed(.databaseCorrupted(nil))
        }
    }

    /// Builds the items off the main actor; what each item derives from its gallery is
    /// computed here, once per change.
    @concurrent
    nonisolated static func items(from rows: [ReadingListItem]) async -> [ContinueItem] {
        rows.map { ContinueItem(gallery: $0.gallery, page: $0.page, pageCount: $0.pageCount) }
    }

    private func apply(_ newItems: [ContinueItem]) {
        if items != newItems { items = newItems }
        if first != newItems.first { first = newItems.first }
        if loadingState != .idle { loadingState = .idle }
    }
}
