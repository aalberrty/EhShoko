import EhFeatures
import SwiftUI

extension EnvironmentValues {
    /// How many times the tab this screen is in was re-selected while it showed its root
    /// (`AppRouter.rootReselectionCount(for:)`). A screen cannot ask the router itself: it does
    /// not know which tab it is in. The list at a stack's root reloads when this changes,
    /// whatever first screen or tab put it there. Outside the tabs bar it stays zero.
    @Entry var tabsBarRootReselections = 0
}

/// Around one tab's stack: what the bar does for every screen of that tab. Its own modifier,
/// so a push, a pop or a re-selection runs this body and not the tab view's.
///
/// - It hands the tab's screens its count of re-selections at the root.
/// - It hides the tab bar while a gallery page or one of its child screens is on top, and
///   shows it for every other screen, at any depth: the bar is this folder's, so it hides
///   itself, from the path, outside the stack. The stack's root asks for the same, but what
///   a root asks for does not always arrive: on iOS 26.0 the bar stayed over the dock of a
///   gallery opened from Shelf's Home. It is still never hidden by the destination, which
///   brings the accessory back a few frames before the bar (`spikes/S3.md` section 3).
/// - On the systems without the accessory it tells the tab's screens what the capsule needs
///   to know of the bottom edge (`TabsBarLegacyEdge`).
struct TabsBarStack: ViewModifier {
    let tab: AppTab

    @Environment(AppRouter.self) private var appRouter

    func body(content: Content) -> some View {
        content
            .environment(\.tabsBarRootReselections, appRouter.rootReselectionCount(for: tab))
            .toolbarVisibility(appRouter.stack(for: tab).hidesBrowseChrome ? .hidden : .automatic, for: .tabBar)
            .modifier(TabsBarLegacyEdgeReader())
    }
}
