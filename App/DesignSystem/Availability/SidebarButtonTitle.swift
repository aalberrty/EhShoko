import SwiftUI

extension EnvironmentValues {
    /// The split view's sidebar button is on this screen's bar, in front of its title: the
    /// root screen of the list column while Ledger's Index is hidden under the tab bar.
    @Entry var titleIsBesideSidebarButton = false
}

extension View {
    /// Marks a split view's detail root whose bar holds the sidebar button.
    func titleBesideSidebarButton(_ isBeside: Bool) -> some View {
        environment(\.titleIsBesideSidebarButton, isBeside)
    }

    /// A large title in the bar's own row (`inlineLarge`), leading.
    ///
    /// On iOS 18 an iPad's tab bar floats in the navigation bar's top row, so the bar lays its
    /// items in the title's row, and an inline large title is laid out from the bar's leading
    /// edge whatever the bar holds there: beside a split view's sidebar button it sits under
    /// the button. There the title takes the system's standard large mode, which the bar then
    /// draws after the button, inline as it does under its tab bar. iOS 26 lays the inline
    /// large title out after leading items: nothing changes there.
    func leadingLargeTitle() -> some View {
        modifier(LeadingLargeTitle())
    }
}

private struct LeadingLargeTitle: ViewModifier {
    @Environment(\.titleIsBesideSidebarButton) private var isBeside

    func body(content: Content) -> some View {
        // The system is the process's, so this `if` never rebuilds the screen; the mode is one
        // modifier with a computed value for the same reason.
        if #available(iOS 26, *) {
            content.toolbarTitleDisplayMode(.inlineLarge)
        } else {
            content.toolbarTitleDisplayMode(isBeside ? .large : .inlineLarge)
        }
    }
}
