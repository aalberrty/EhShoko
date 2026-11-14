import SwiftUI

/// A flexible space between bottom toolbar items (the wizard's and the offer's Back, Skip and
/// Next): `ToolbarSpacer(.flexible, placement: .bottomBar)` on iOS 26, which also splits the
/// items into separate glass groups; nothing on iOS 18, where the items share the system's
/// bottom toolbar and are laid out by it.
struct BottomToolbarSpacer: ToolbarContent {
    var body: some ToolbarContent {
        if #available(iOS 26, *) {
            ToolbarSpacer(.flexible, placement: .bottomBar)
        }
    }
}
