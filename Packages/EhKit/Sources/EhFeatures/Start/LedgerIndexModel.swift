import Dependencies
import EhCore
import EhModels
import EhNetworking
import Foundation
import Observation

/// What Ledger's Index shows besides the shared stores (`ledger.md` section 2): the number
/// of galleries in History, the saved quick searches, the favourites folders' counts, and
/// the gallery link the bar's paste button opens.
///
/// Owned by `LedgerIndexView` with `@State`, so it goes when the Index goes (a change of the
/// first screen releases it). `init` reads nothing; the view's `.task`s start the
/// observations and cancel them when it disappears.
@Observable
public final class LedgerIndexModel {
    /// How many galleries History holds; `nil` until the database first answers.
    public private(set) var historyCount: Int?
    /// The saved quick searches, in the user's order.
    public private(set) var quickSearches: [QuickSearchWord] = []

    /// The favourites folders' counts, asked for while nobody has loaded a favourites page
    /// this session; a pull to refresh asks again.
    public let folderCounts = FavoriteFolderCounts()

    @ObservationIgnored @Dependency(\.database) private var database
    @ObservationIgnored @Dependency(\.clipboardClient) private var clipboard

    public init() {}

    /// Follows History's size until the calling task is cancelled.
    public func observeHistoryCount() async {
        do {
            for try await count in database.observeHistoryCount() where count != historyCount {
                historyCount = count
            }
        } catch {
            // Only a broken database fails an observation; the row then shows no number.
        }
    }

    /// Follows the saved quick searches until the calling task is cancelled.
    public func observeQuickSearches() async {
        do {
            for try await words in database.observeQuickSearchWords() where words != quickSearches {
                quickSearches = words
            }
        } catch {
            // As above: the section keeps what it had.
        }
    }

    /// The gallery link on the clipboard, as the app's own link (`EhURL.appLink`) so that the
    /// shell opens it the way it opens a shared one; `nil` when there is none.
    ///
    /// The clipboard is first checked by pattern, which shows no paste prompt, so the system
    /// asks to paste only when there probably is a link to read.
    public func pastedGalleryLink() async -> URL? {
        guard await clipboard.hasProbableURL() else { return nil }
        return clipboard.url().flatMap(EhURL.appLink(for:))
    }
}
