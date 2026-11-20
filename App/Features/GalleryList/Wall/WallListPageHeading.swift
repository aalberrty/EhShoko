import SwiftUI

extension View {
    /// For a page's divider that stands in the stack between the pages' lazy grids
    /// (`WallListPage`): among VoiceOver's elements only while it is on screen.
    ///
    /// A lazy grid has only the cells near the screen, so the elements end where its built
    /// cells end, and VoiceOver scrolls on from there. A divider further down that is there
    /// all the same would be the next element after the last built cell: a swipe would jump
    /// to "Page 3" over the rows of page 2 that are not built yet, and back over the rows
    /// above the screen. In the one grid a numbered list was before, a divider off screen
    /// was not built either.
    func spokenOnlyOnScreen() -> some View {
        modifier(SpokenOnlyOnScreen())
    }
}

private struct SpokenOnlyOnScreen: ViewModifier {
    @State private var isOnScreen = false

    func body(content: Content) -> some View {
        content
            .accessibilityHidden(!isOnScreen)
            .onScrollVisibilityChange(threshold: 0.01) { isOnScreen = $0 }
    }
}
