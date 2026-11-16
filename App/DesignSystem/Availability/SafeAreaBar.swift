import SwiftUI

extension View {
    /// Places `content` at the bottom of the screen, above the scrolling content, which then
    /// insets by its height: `safeAreaBar(edge: .bottom)` with the system's soft scroll edge
    /// effect on iOS 26; `safeAreaInset(edge: .bottom)` over a gradient from the look's
    /// background on iOS 18.
    ///
    /// The bar draws no surface of its own: glass shapes inside it (`glassSurface`,
    /// `GlassGroup`) are the controls. Not for a screen inside a tab whose iOS 18 accessory
    /// capsule sits in the same inset (`legacyTabAccessory`). A screen that does not stand on
    /// the look's background turns the iOS 18 gradient off with `legacyBottomBarFade(.hidden)`.
    func bottomBar(spacing: CGFloat? = nil, @ViewBuilder content: () -> some View) -> some View {
        modifier(BottomBar(spacing: spacing, bar: content()))
    }

    /// Whether the `bottomBar`s inside draw their iOS 18 gradient, which fades the rows into
    /// the look's background before they meet the controls. A screen over something else
    /// (Wall's search over its material) passes `.hidden`: the gradient would lay a band of the
    /// look's background over it, and the rows meet the controls with no band, as they pass
    /// under the system's bars. iOS 26 keeps the system's scroll edge effect either way.
    func legacyBottomBarFade(_ visibility: Visibility) -> some View {
        environment(\.legacyBottomBarFade, visibility)
    }

    /// Pins `content` under the navigation bar, above the scrolling content (Top's period
    /// control, the Library's switch, search scopes): `safeAreaBar(edge: .top)` on iOS 26, where
    /// the system's scroll edge effect carries the bar's glass down behind it;
    /// `safeAreaInset(edge: .top)` on the bar material with a hairline on iOS 18.
    ///
    /// A bar that comes and goes (the list's find bar) stays attached and passes
    /// `isPresented`, so the screen under it keeps its identity and state; while it is `false`
    /// nothing is drawn, not even the iOS 18 material, which would otherwise reach up under the
    /// navigation bar.
    func topBar(isPresented: Bool = true, spacing: CGFloat? = nil, @ViewBuilder content: () -> some View) -> some View {
        modifier(TopBar(isPresented: isPresented, spacing: spacing, bar: content()))
    }

    /// Around screens whose `bottomBar` is `height` high, where that height is switched inside
    /// an animation (the shell's host switches it while its bar turns into a dock). On iOS 26
    /// the screens follow the animation and this adds nothing. On iOS 18 they take the new
    /// height at once, and what is outside this view keeps the animation.
    ///
    /// On iOS 18 a bottom inset that changes inside an animation hangs the app when it reaches
    /// a `List` that has just been pushed under a navigation bar with a large title (also the
    /// inline large one). The list is laid out at the animation's in-between sizes; the bar's
    /// height follows the list's offset and the list's top inset follows the bar's height, and
    /// the two flip between the expanded and the collapsed bar inside one layout pass, which
    /// never ends. A scroll view, or a small title, does not do it.
    func bottomBarHeightChangesAtOnce(_ height: CGFloat) -> some View {
        modifier(BottomBarHeightChange(height: height))
    }
}

extension EnvironmentValues {
    /// Set by `legacyBottomBarFade(_:)`; `.hidden` turns the iOS 18 gradient off.
    @Entry var legacyBottomBarFade: Visibility = .automatic
}

private struct BottomBar<Bar: View>: ViewModifier {
    let spacing: CGFloat?
    let bar: Bar
    @Environment(\.look) private var look
    @Environment(\.legacyBottomBarFade) private var fade

    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content
                .safeAreaBar(edge: .bottom, spacing: spacing) { bar }
                .scrollEdgeEffectStyle(.soft, for: .bottom)
        } else {
            content.safeAreaInset(edge: .bottom, spacing: spacing) {
                bar.background {
                    if fade != .hidden {
                        // Reaches a little above the bar and down under the home indicator, so
                        // the rows fade out before they meet the controls.
                        LinearGradient(
                            colors: [look.background.opacity(0), look.background.opacity(0.92)],
                            startPoint: .top, endPoint: .bottom
                        )
                        .padding(.top, -24)
                        .ignoresSafeArea(edges: .bottom)
                        .allowsHitTesting(false)
                    }
                }
            }
        }
    }
}

private struct BottomBarHeightChange: ViewModifier {
    let height: CGFloat

    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content
        } else {
            // Only the update that changes the height loses its animation.
            content.transaction(value: height) { $0.animation = nil }
        }
    }
}

private struct TopBar<Bar: View>: ViewModifier {
    let isPresented: Bool
    let spacing: CGFloat?
    let bar: Bar

    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.safeAreaBar(edge: .top, spacing: spacing) {
                if isPresented { bar }
            }
        } else {
            content.safeAreaInset(edge: .top, spacing: spacing) {
                if isPresented {
                    bar
                        .frame(maxWidth: .infinity)
                        .background(.bar)
                        .overlay(alignment: .bottom) { Divider() }
                }
            }
        }
    }
}
