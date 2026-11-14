import SwiftUI

// The tab bar's accessory (Shelf's Continue) and its fallback, after spike S3
// (`Design/designs/spikes/S3.md`, "The pattern A1 must use"):
// - 26.1 and later: the system accessory, `tabViewBottomAccessory(isEnabled:)`, always applied
//   and switched with `isEnabled`. Adding or removing the modifier with an `if` rebuilds every
//   tab, so it never happens.
// - 26.0 and iOS 18: a capsule in a bottom inset on each screen (never on the stack, where it
//   covers the screen's own inset, and never on the search surface, where it rides above the
//   keyboard). 26.0 can add or remove the system accessory only by rebuilding every tab.

enum TabAccessoryKind {
    /// Whether the system accessory is used: 26.1 and later.
    static var usesSystemAccessory: Bool {
        if #available(iOS 26.1, *) { true } else { false }
    }
}

extension View {
    /// On the `TabView`. 26.1 and later: `tabViewBottomAccessory(isEnabled:)`, whose glass is
    /// the system's, so `content` draws no background. Elsewhere: nothing.
    ///
    /// `content` reads `tabViewBottomAccessoryPlacement` and lays out its compact form unless
    /// the placement is `.expanded` (it is `nil` while the accessory is being removed).
    func tabAccessory(isEnabled: Bool, @ViewBuilder content: () -> some View) -> some View {
        modifier(TabAccessory(isEnabled: isEnabled, accessory: content()))
    }

    /// On the `TabView`. 26.1 and later: the bar minimises as a list scrolls down and the
    /// accessory moves inline. 26.0 and iOS 18: nothing, because the capsule would float above
    /// a minimised bar.
    func tabBarMinimizesOnScroll() -> some View {
        modifier(TabBarMinimizesOnScroll())
    }

    /// On each screen inside a tab's stack that keeps the bar, outside the screen's own insets.
    /// 26.0 and iOS 18: `content` in a capsule of glass (26.0) or regular material (iOS 18)
    /// in a bottom inset above the tab bar, while `isVisible`. 26.1 and later: nothing.
    func legacyTabAccessory(isVisible: Bool, @ViewBuilder content: () -> some View) -> some View {
        modifier(LegacyTabAccessory(isVisible: isVisible, accessory: content()))
    }
}

private struct TabAccessory<Accessory: View>: ViewModifier {
    let isEnabled: Bool
    let accessory: Accessory

    func body(content: Content) -> some View {
        if #available(iOS 26.1, *) {
            content.tabViewBottomAccessory(isEnabled: isEnabled) { accessory }
        } else {
            content
        }
    }
}

private struct TabBarMinimizesOnScroll: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.1, *) {
            content.tabBarMinimizeBehavior(.onScrollDown)
        } else {
            content
        }
    }
}

private struct LegacyTabAccessory<Accessory: View>: ViewModifier {
    let isVisible: Bool
    let accessory: Accessory

    /// The system's expanded slot on a 402 pt phone is 360 × 48 (S3, question 4).
    private static var height: CGFloat { 48 }
    private static var sideMargin: CGFloat { 21 }

    func body(content: Content) -> some View {
        if TabAccessoryKind.usesSystemAccessory {
            content
        } else {
            // The inset is always present and its content switches, so showing or hiding the
            // capsule never changes the screen's structure.
            content.safeAreaInset(edge: .bottom, spacing: 0) {
                if isVisible {
                    accessory
                        .frame(maxWidth: .infinity, minHeight: Self.height)
                        .contentShape(.capsule)
                        .glassSurface(in: .capsule, isInteractive: true)
                        .padding(.horizontal, Self.sideMargin)
                        .padding(.bottom, 6)
                        .transition(.opacity)
                }
            }
        }
    }
}
