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
/// so a re-selection runs this body and not the tab view's.
///
/// - It hands the tab's screens its count of re-selections at the root.
/// - On iOS 26.0 it hides the tab bar on gallery routes (`TabsBarHiding`).
/// - On the systems without the accessory it tells the tab's screens what the capsule needs
///   to know of the bottom edge (`TabsBarLegacyEdge`).
struct TabsBarStack: ViewModifier {
    let tab: AppTab

    @Environment(AppRouter.self) private var appRouter

    func body(content: Content) -> some View {
        content
            .environment(\.tabsBarRootReselections, appRouter.rootReselectionCount(for: tab))
            .modifier(TabsBarHiding(tab: tab))
            .modifier(TabsBarLegacyEdgeReader())
    }
}

/// Hides the tab bar while a gallery page or one of its child screens is on top of this
/// tab's stack, from the path, outside the stack. On iOS 26.0 only.
///
/// Every stack's root already asks for this (`RoutedStack`), and on iOS 18 and from iOS 26.1
/// that is enough. On iOS 26.0 what the root asks for does not always arrive: the bar stayed
/// over the dock of a gallery opened from Shelf's Home, and asking from the tab's own content
/// hides it. It must not be asked twice elsewhere: on iOS 18.5 the two requests fight when a
/// list is pushed over a gallery, the bar stays hidden, the list is laid out under its top
/// bar and the app never comes to rest. It is never asked by the destination either, which
/// brings the accessory back a few frames before the bar (`spikes/S3.md` section 3).
private struct TabsBarHiding: ViewModifier {
    let tab: AppTab

    @Environment(AppRouter.self) private var appRouter

    func body(content: Content) -> some View {
        // The same for the whole life of the process, so this `if` never rebuilds a tab,
        // and on the other systems a push or a pop does not run this body.
        if TabAccessoryKind.isIOS26_0 {
            content.toolbarVisibility(appRouter.stack(for: tab).hidesBrowseChrome ? .hidden : .automatic, for: .tabBar)
        } else {
            content
        }
    }
}
