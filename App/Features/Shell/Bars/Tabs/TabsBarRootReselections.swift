import EhFeatures
import SwiftUI

extension EnvironmentValues {
    /// How many times the tab this screen is in was re-selected while it showed its root
    /// (`AppRouter.rootReselectionCount(for:)`). A screen cannot ask the router itself: it does
    /// not know which tab it is in. The list at a stack's root reloads when this changes,
    /// whatever first screen or tab put it there. Outside the tabs bar it stays zero.
    @Entry var tabsBarRootReselections = 0
}

/// Around one tab's stack: hands that tab's screens its re-selection count. Its own
/// modifier, so a re-selection runs this body and not the tab view's.
struct TabsBarRootReselections: ViewModifier {
    let tab: AppTab

    @Environment(AppRouter.self) private var appRouter

    func body(content: Content) -> some View {
        content.environment(\.tabsBarRootReselections, appRouter.rootReselectionCount(for: tab))
    }
}
