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
    /// Continue itself (`spikes/S5.md` sections 3.4 and 4.5).
    private var isEnabled: Bool {
        guard TabAccessoryKind.usesSystemAccessory, continueModel.first != nil else { return false }
        let stack = router.selectedStack
        let showsLeadingColumn = hasLeadingColumn && sizeClass == .regular && router.selectedTab == .home
        return !stack.hidesBrowseChrome && stack.sideGallery == nil && !showsLeadingColumn
    }
}

extension EnvironmentValues {
    /// Whether the screens of this stack show the capsule that stands in for the accessory:
    /// true for the tabs' stacks but the search tab's, false everywhere else.
    @Entry var tabsBarKeepsLegacyAccessory = false
}

/// On iOS 18 and iOS 26.0, which have no accessory that can be switched off without
/// rebuilding every tab: the same content in a capsule in a bottom inset, on each screen that
/// keeps the tab bar, outside the screen's own insets (`spikes/S3.md` section 5). On later
/// systems it reads nothing and adds nothing.
struct TabsBarLegacyAccessory: ViewModifier {
    /// Whether this screen's route keeps the tab bar.
    let isAllowed: Bool

    @Environment(\.tabsBarKeepsLegacyAccessory) private var keepsAccessory
    @Environment(ContinueModel.self) private var continueModel: ContinueModel?

    func body(content: Content) -> some View {
        content.legacyTabAccessory(isVisible: isVisible) {
            TabsBarAccessory()
        }
    }

    /// What is in progress is read last, and so only where a capsule can show: on later
    /// systems, under `command` and on gallery pages a change of it redraws no screen.
    private var isVisible: Bool {
        !TabAccessoryKind.usesSystemAccessory && keepsAccessory && isAllowed && continueModel?.first != nil
    }
}
