import SwiftUI

extension View {
    /// Places `content` at the bottom of the screen, above the scrolling content, which then
    /// insets by its height: `safeAreaBar(edge: .bottom)` with the system's soft scroll edge
    /// effect on iOS 26; `safeAreaInset(edge: .bottom)` over a gradient from the look's
    /// background on iOS 18.
    ///
    /// The bar draws no surface of its own: glass shapes inside it (`glassSurface`,
    /// `GlassGroup`) are the controls. Not for a screen inside a tab whose iOS 18 accessory
    /// capsule sits in the same inset (`legacyTabAccessory`).
    func bottomBar(spacing: CGFloat? = nil, @ViewBuilder content: () -> some View) -> some View {
        modifier(BottomBar(spacing: spacing, bar: content()))
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
}

private struct BottomBar<Bar: View>: ViewModifier {
    let spacing: CGFloat?
    let bar: Bar
    @Environment(\.look) private var look

    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content
                .safeAreaBar(edge: .bottom, spacing: spacing) { bar }
                .scrollEdgeEffectStyle(.soft, for: .bottom)
        } else {
            content.safeAreaInset(edge: .bottom, spacing: spacing) {
                bar.background {
                    // Reaches a little above the bar and down under the home indicator, so the
                    // rows fade out before they meet the controls.
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
