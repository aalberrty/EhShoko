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
            // Under `tabs` the navigation bar stays: it holds the account button the shell
            // adds, and brings the system's edge under the status bar.
            .toolbarVisibility(hasTopBar ? .automatic : .hidden, for: .navigationBar)
            .modifier(WallStatusBarFade(isActive: !hasTopBar))
        case .list(.favorites):
            LibraryScreen()
        case .list(let kind):
            GalleryListScreen(context: .place(kind))
        }
    }

    /// Front Page has no top bar under `command`, where nothing would be in it.
    private var hasTopBar: Bool {
        chrome.bar == .tabs
    }
}

/// The short fade the covers run under at the top of a screen with no top bar
/// (`wall.md` section 2), so the status bar stays legible over them.
///
/// It is drawn by hand on every system: the scroll edge effect that replaces such fades on
/// iOS 26 comes with a navigation bar, and a screen without one gets none, not from a top
/// `safeAreaBar` nor from `scrollEdgeEffectStyle` or `scrollEdgeEffectHidden` (tried on
/// iOS 26.3). It covers the status bar's area and nothing below it, so at rest it lies on the
/// background and is not seen.
private struct WallStatusBarFade: ViewModifier {
    let isActive: Bool

    @Environment(\.look) private var look

    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            if isActive {
                // A line of no height at the safe area's top edge, whose background reaches up
                // to the screen's edge: the status bar's area, which is nothing in landscape on
                // a phone. A view of fixed height would keep that height when it ignores the
                // safe area; a background takes the area it is given.
                Color.clear
                    .frame(height: 0)
                    .background {
                        LinearGradient(
                            stops: [
                                .init(color: look.background, location: 0.35),
                                .init(color: look.background.opacity(0), location: 1),
                            ],
                            startPoint: .top, endPoint: .bottom
                        )
                        .ignoresSafeArea(edges: .top)
                    }
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }
}
