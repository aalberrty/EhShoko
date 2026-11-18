import SwiftUI

// The tab bar's accessory (Shelf's Continue) and its fallback, after spike S3
// (`Design/designs/spikes/S3.md`, "The pattern A1 must use"):
// - 26.1 and later: the system accessory, `tabViewBottomAccessory(isEnabled:)`, always applied
//   and switched with `isEnabled`. Adding or removing the modifier with an `if` rebuilds every
//   tab, so it never happens.
// - 26.0 and iOS 18: a capsule, which 26.0 needs because it can add or remove the system
//   accessory only by rebuilding every tab. Like the bottom chrome (`spikes/S2.md` section 1.5)
//   it is an overlay on each tab's stack, above the tab bar, and each screen keeps its height
//   free inside the stack: an inset on the stack itself would not reach the screens' scroll
//   views. It is never on the search surface, and never above a keyboard.

enum TabAccessoryKind {
    /// Whether the system accessory is used: 26.1 and later.
    static var usesSystemAccessory: Bool {
        if #available(iOS 26.1, *) { true } else { false }
    }

    /// iOS 26.0: the first system with the accessory, which draws the capsule instead. Its tab
    /// bar does not always hide when a stack's root asks for it, so the tab asks as well
    /// (`TabsBarStack`).
    static var isIOS26_0: Bool {
        if #available(iOS 26, *) { !usesSystemAccessory } else { false }
    }

    /// Whether the tab bar tucks away as a list scrolls down (`tabBarMinimizesOnScroll()`):
    /// 26.1 and later. Shelf's moving preview shows it only where it happens. Read off the
    /// main actor by the stage's playback.
    nonisolated static var tabBarMinimizesOnScroll: Bool {
        if #available(iOS 26.1, *) { true } else { false }
    }
}

/// Tells an accessory's content whether it is in the bar's inline slot, where it lays out its
/// compact form.
///
/// 26.1 and later: compact unless `tabViewBottomAccessoryPlacement` is `.expanded`. It is `nil`
/// while the accessory is being removed, and the full form must not be laid into an inline slot
/// (`spikes/S3.md`, question 4). Elsewhere the content is the capsule's and always full.
struct TabAccessoryPlacementReader<Content: View>: View {
    @ViewBuilder let content: (_ isCompact: Bool) -> Content

    var body: some View {
        if #available(iOS 26, *), TabAccessoryKind.usesSystemAccessory {
            SystemTabAccessoryPlacement(content: content)
        } else {
            content(false)
        }
    }
}

@available(iOS 26, *)
private struct SystemTabAccessoryPlacement<Content: View>: View {
    let content: (_ isCompact: Bool) -> Content

    @Environment(\.tabViewBottomAccessoryPlacement) private var placement

    var body: some View {
        content(placement != .expanded)
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

    /// The accessory's content in the capsule that stands in for it on 26.0 and iOS 18: glass
    /// (26.0) or regular material (iOS 18), as high as the system's slot and as far from the
    /// sides, with the gap it keeps above the tab bar. 26.1 and later have the system's
    /// accessory and never draw this.
    func legacyTabAccessoryCapsule() -> some View {
        modifier(LegacyTabAccessoryCapsule())
    }
}

enum LegacyTabAccessoryMetrics {
    /// The system's expanded slot on a 402 pt phone is 360 × 48 (S3, question 4).
    static var height: CGFloat { 48 }
    static var sideMargin: CGFloat { 21 }
    static var gap: CGFloat { 6 }
    /// What a screen keeps free at its bottom while the capsule is over it.
    static var room: CGFloat { height + gap }
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
    // The same system check as `TabAccessoryKind.tabBarMinimizesOnScroll`.
    func body(content: Content) -> some View {
        if #available(iOS 26.1, *) {
            content.tabBarMinimizeBehavior(.onScrollDown)
        } else {
            content
        }
    }
}

private struct LegacyTabAccessoryCapsule: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, minHeight: LegacyTabAccessoryMetrics.height)
            .contentShape(.capsule)
            .glassSurface(in: .capsule, isInteractive: true)
            .padding(.horizontal, LegacyTabAccessoryMetrics.sideMargin)
            .padding(.bottom, LegacyTabAccessoryMetrics.gap)
    }
}
