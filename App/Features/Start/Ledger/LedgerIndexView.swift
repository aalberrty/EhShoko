import EhCore
import EhFeatures
import EhModels
import SwiftUI

/// Ledger's first screen, the Index (`ledger.md` section 2): Continue, the lists, the
/// favourites folders and the saved searches, all local but the folders' counts, so it is
/// whole in its first frame.
///
/// On a phone, and wherever it is the stack's root, it is one scroll (`LedgerIndexPage`) and
/// its rows push over it. On regular width the shell shows it as the split view's sidebar
/// (`chrome.isLeadingColumn`), and it is the system's sidebar list (`LedgerIndexColumn`)
/// whose rows choose the list beside it. The router's path is the same in both, so nothing
/// is converted when the width changes.
struct LedgerIndexView: View {
    @State private var model = LedgerIndexModel()
    @State private var editsQuickSearches = false
    @State private var hud: HUDConfiguration?

    @Environment(\.chrome) private var chrome
    @Environment(AccountSession.self) private var accountSession
    @Environment(AppRouter.self) private var appRouter
    @Environment(StackRouter.self) private var stack
    @Environment(\.openURL) private var openURL

    var body: some View {
        let navigation = LedgerIndexNavigation(appRouter: appRouter, stack: stack)
        Group {
            if chrome.isLeadingColumn {
                LedgerIndexColumn(model: model, navigation: navigation) { editsQuickSearches = true }
            } else {
                LedgerIndexPage(model: model, navigation: navigation) { editsQuickSearches = true }
            }
        }
        // The bar's back menu and VoiceOver's screen name; the title itself is drawn by the
        // Index in the look's title face.
        .navigationTitle(L10n.Localizable.Shell.Place.index)
        .toolbarTitleDisplayMode(.inline)
        // The Index keeps its account button under `command`; under `tabs` the shell adds it.
        .startAccountButton()
        // The command bar's trailing circle: a gallery link from the clipboard. Beside the
        // iPad column the shell drops it, and under `tabs` there is no bar to hold it.
        .barControl(Self.pasteControl) { _ in
            Task { await openPastedLink() }
        }
        .sheet(isPresented: $editsQuickSearches) {
            QuickSearchSheet { keyword in
                editsQuickSearches = false
                navigation.run(keyword)
            }
        }
        .hud($hud)
        .task { await model.observeHistoryCount() }
        .task { await model.observeQuickSearches() }
        // Again when the user signs in: an Index first shown signed out has asked nothing.
        .task(id: accountSession.isLoggedIn) { await model.folderCounts.loadIfUnknown() }
        // Everything the Index shows but the counts is local: it is the first screen's
        // content as soon as it is on screen. Only the first call in the process counts.
        .onAppear { PerformanceSignposts.contentShown("index") }
    }

    private static let pasteControl = BarControl.button(
        systemImage: "doc.on.clipboard", title: L10n.Localizable.Search.Link.title, showsDot: false
    )

    /// Hands the link to the app as a shared link is handed to it, so the shell resolves it
    /// and shows the gallery in its sheet.
    private func openPastedLink() async {
        if let link = await model.pastedGalleryLink() {
            openURL(link)
        } else {
            hud = .error
        }
    }
}
