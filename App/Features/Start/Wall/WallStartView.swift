import EhFeatures
import EhModels
import SwiftUI

/// Wall's first screen (`wall.md` section 2): the current place's list, whatever place that
/// is. On Front Page the list has no title and the Continue banner is its header when Continue
/// is not in the bar's chrome. Other places are their list as it is anywhere else, with its own
/// title.
///
/// The navigation bar stays on Front Page under both bars, empty but for the list's More menu
/// (Find, Reload, the densities) as one floating button: hidden, it took that menu with it.
/// It also brings the system's edge under the status bar, which keeps the status bar legible
/// over the covers.
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
            // No title is drawn, but the bar keeps the place's name, as Shelf's Home does: for
            // Back and the app switcher, and as the bar's name for VoiceOver, which otherwise
            // read the hosting controller's type name.
            .hiddenBarTitle(GalleryListKind.frontpage.title)
        case .list(.favorites):
            LibraryScreen()
        case .list(let kind):
            GalleryListScreen(context: .place(kind))
        }
    }
}
