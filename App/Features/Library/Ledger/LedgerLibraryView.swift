import EhFeatures
import SwiftUI

/// Ledger's library (`ledger.md` section 7): the folder grid of the Index on its own. A row
/// for every folder at once, then the ten folders with their colours, names and counts; a tap
/// pushes that folder's list, which the list part draws. Signed out, the shared sign-in state.
///
/// It is what the Library tab's Favourites segment and the place menu's Favourites show.
/// Under `tabs` the Library tab draws the title with its switch, so the screen draws none.
///
/// The galleries of a folder are never shown here: each folder is pushed as a list with a
/// model of its own (`Route.favoritesFolder`), so the shared model's galleries go unused under
/// Ledger and nothing loads them. What the screen requests is the folders' counts, once, when
/// nobody has loaded a favourites page this session.
struct LedgerLibraryView: View {
    /// `LibraryScreen`'s model. Ledger pushes each folder as its own list and reads none of it.
    let model: FavoritesModel

    /// The counts request, shared with the Index: it asks only while the counts are unknown,
    /// so the library and the Index between them ask once.
    @State private var counts = FavoriteFolderCounts()
    /// The Library tab's re-selections seen while this screen showed its root.
    @State private var reselection: Int?

    @Environment(AccountSession.self) private var accountSession
    @Environment(AppRouter.self) private var appRouter
    @Environment(StackRouter.self) private var stack
    @Environment(\.chrome) private var chrome
    @Environment(\.look) private var look

    var body: some View {
        let isSignedIn = accountSession.isLoggedIn
        Group {
            if isSignedIn {
                LedgerLibraryPage(showsTitle: hasTitle, open: open) {
                    await counts.refresh()
                }
            } else {
                ListSignInState(kind: .favorites)
                    // No title on the page: the bar's is always shown.
                    .ledgerLibraryBarTitle(isShown: hasTitle, isAlwaysVisible: true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { look.background.ignoresSafeArea() }
        // Again when the user signs in on this screen.
        .task(id: isSignedIn) { await counts.loadIfUnknown() }
        // Re-selecting the Library tab at its root reloads what this screen shows: the counts.
        .onChange(of: appRouter.rootReselectionCount(for: .library)) { _, count in
            reselection = count
        }
        .task(id: reselection) {
            if reselection != nil { await counts.refresh() }
        }
    }

    /// Under `tabs` the Library tab names the screen above its switch.
    private var hasTitle: Bool {
        chrome.bar != .tabs
    }

    /// A folder's list, or every folder's (`-1`), over the library.
    private func open(_ folder: Int) {
        stack.push(.favoritesFolder(folder))
    }
}
