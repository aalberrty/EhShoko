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
final class LedgerIndexModel {
    /// How many galleries History holds; `nil` until the database first answers.
    private(set) var historyCount: Int?
    /// The saved quick searches, in the user's order.
    private(set) var quickSearches: [QuickSearchWord] = []

    /// The counts are asked for once per Index, when nobody has loaded a favourites page
    /// this session; after that a pull to refresh asks again.
    @ObservationIgnored private var hasRequestedCounts = false

    @ObservationIgnored @Dependency(\.database) private var database
    @ObservationIgnored @Dependency(\.ehClient) private var client
    @ObservationIgnored @Dependency(\.userStore) private var userStore
    @ObservationIgnored @Dependency(\.accountSession) private var accountSession
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

    /// Asks for the folders' counts when no favourites page was loaded this session: one
    /// favourites request, signed in only. Until it answers the counts are absent.
    func loadFolderCountsIfUnknown() async {
        guard !hasRequestedCounts, userStore.favoriteFolderCounts.isEmpty else { return }
        hasRequestedCounts = true
        await refreshFolderCounts()
    }

    /// Pull to refresh: the first page of All favourites, for the counts it lists. The page
    /// itself is not kept; `UserStore` takes the counts and the folders' names.
    func refreshFolderCounts() async {
        guard accountSession.isLoggedIn else { return }
        do {
            let page = try await client.favorites(category: -1)
            userStore.updateFavoriteFolders(page.folders)
        } catch {
            // Offline or cancelled: the Index is local apart from the counts, and shows what
            // it has.
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
