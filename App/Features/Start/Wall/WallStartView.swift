import EhFeatures
import SwiftUI

/// Wall's first screen (`wall.md` section 2): the current place's list, whatever place that
/// is. On Front Page the list has no title, the covers run to the top, and the Continue banner
/// is its header when Continue is not in the bar's chrome. Other places are their list as it
/// is anywhere else, with its own title.
///
/// It keeps no account button: Settings is in the place menu, and under `tabs` the shell adds
/// the button around this screen.
struct WallStartView: View {
    @Environment(AppRouter.self) private var appRouter
    @Environment(\.chrome) private var chrome

    var body: some View {
        // Under `command` the place menu replaces the root's list in place; under `tabs` the
        // root is Front Page.
        switch chrome.bar == .command ? appRouter.rootPlace : .start {
        case .start:
            GalleryListScreen(context: .place(.frontpage, embedsInStart: true)) {
                if !chrome.continueIsInChrome {
                    WallContinueBanner()
                }
            }
            // No top bar on Front Page. Under `tabs` there is one all the same: it holds the
            // account button the shell adds.
            .toolbarVisibility(chrome.bar == .command ? .hidden : .automatic, for: .navigationBar)
        case .list(.favorites):
            LibraryScreen()
        case .list(let kind):
            GalleryListScreen(context: .place(kind))
        }
    }
}
