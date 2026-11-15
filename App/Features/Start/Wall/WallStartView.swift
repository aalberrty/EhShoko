import EhFeatures
import SwiftUI

/// Wall's first screen (`wall.md` section 2): the current place's list, with the Continue
/// banner as its header on Front Page when Continue is not in the bar's chrome.
///
/// **Adapter.** Until task B2 builds it, this is the place's list alone, without the banner.
/// B2 replaces this file and keeps the initializer, which is what `StartScreen` calls.
struct WallStartView: View {
    @Environment(AppRouter.self) private var appRouter
    @Environment(\.chrome) private var chrome

    var body: some View {
        // Under `command` the place menu replaces the root's list in place; under `tabs` the
        // root is Front Page.
        switch chrome.bar == .command ? appRouter.rootPlace : .start {
        case .start:
            GalleryListScreen(context: .place(.frontpage))
        case .list(.favorites):
            LibraryScreen()
        case .list(let kind):
            GalleryListScreen(context: .place(kind))
        }
    }
}
