import EhFeatures
import SwiftUI

/// The accessory and when it is on. Its own modifier, so that a push or a pop in the selected
/// stack runs this body and not the tab view's.
///
/// The modifier is always applied and only switched: adding or removing it with an `if`
/// rebuilds every tab (`spikes/S3.md`, question 2).
struct TabsBarAccessoryHost: ViewModifier {
    let router: AppRouter
    let hasLeadingColumn: Bool

    @Environment(ContinueModel.self) private var continueModel
    @Environment(\.horizontalSizeClass) private var sizeClass

    func body(content: Content) -> some View {
        content.tabAccessory(isEnabled: isEnabled) {
            TabsBarAccessory()
        }
    }

    /// On while something is in progress and the selected stack shows the tab bar: hiding the
    /// bar does not hide its accessory, so a gallery page switches it off here. Off beside a
    /// side gallery, whose dock it would lift, and while the Index column shows, which has
    /// Continue itself (`spikes/S5.md` sections 3.4 and 4.5); on while the Index is hidden.
    ///
    /// Off on the search surface too, the Search tab's root: its field bar is already a bar
    /// above the tab bar, and a third row between the two takes the room the suggestions
    /// have. The capsule of the older systems is never there either. Results pushed over the
    /// surface are a list like any other and have it.
    private var isEnabled: Bool {
        guard TabAccessoryKind.usesSystemAccessory, continueModel.first != nil else { return false }
        let stack = router.selectedStack
        let showsLeadingColumn = hasLeadingColumn && sizeClass == .regular && router.selectedTab == .home
            && !stack.isLeadingColumnHidden
        let showsSearchSurface = router.selectedTab == .search && stack.isAtRoot
        return !stack.hidesBrowseChrome && stack.sideGallery == nil && !showsLeadingColumn && !showsSearchSurface
    }
}
