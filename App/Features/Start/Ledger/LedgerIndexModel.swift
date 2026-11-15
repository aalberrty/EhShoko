import Dependencies
import EhCore
import EhFeatures
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
final class LedgerIndexModel {
    /// How many galleries History holds; `nil` until the database first answers.
    private(set) var historyCount: Int?
    /// The saved quick searches, in the user's order.
    private(set) var quickSearches: [QuickSearchWord] = []

    /// The favourites folders' counts, asked for while nobody has loaded a favourites page
    /// this session; a pull to refresh asks again.
    let folderCounts = FavoriteFolderCounts()

    @ObservationIgnored @Dependency(\.database) private var database
    @ObservationIgnored @Dependency(\.clipboardClient) private var clipboard

    /// Follows History's size until the calling task is cancelled.
    func observeHistoryCount() async {
        do {
            for try await count in database.observeHistoryCount() where count != historyCount {
                historyCount = count
            }
        } catch {
            // Only a broken database fails an observation; the row then shows no number.
        }
    }

    /// Follows the saved quick searches until the calling task is cancelled.
    func observeQuickSearches() async {
        do {
            for try await words in database.observeQuickSearchWords() where words != quickSearches {
                quickSearches = words
            }
        } catch {
            // As above: the section keeps what it had.
        }
    }

    /// The gallery link on the clipboard, as the app's own link so that the shell opens it
    /// the way it opens a shared one; `nil` when there is none.
    ///
    /// The clipboard is first checked by pattern, which shows no paste prompt, so the system
    /// asks to paste only when there probably is a link to read.
    func pastedGalleryLink() async -> URL? {
        guard await clipboard.hasProbableURL(), let url = clipboard.url(), EhURL.isHandleable(url),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return nil }
        components.scheme = Self.appScheme
        return components.url
    }

    /// The scheme the share extension rewrites links to, which `EhURL.resolvingAppScheme`
    /// turns back.
    private static let appScheme = "ehshoko"
}
