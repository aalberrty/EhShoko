import SwiftUI

// The one place that picks Liquid Glass (iOS 26) or its iOS 18 stand-in. Call sites use these
// instead of `glassEffect`, `GlassEffectContainer` or the `.glass` button styles directly.
// On iOS 26 every helper here is glass: none swaps it for a material
// (`Design/designs/README.md` sections 9.4 and 13). Glass never goes inside scrolling content
// and never on glass; the helpers cannot check that, the call sites must.

/// The material a glass surface falls back to on iOS 18.
enum GlassFallback {
    /// `.regularMaterial`: the default for controls over content.
    case regular
    /// `.thinMaterial`: the command bar's three capsules.
    case thin
}

extension View {
    /// Regular glass behind the view in `shape`; on iOS 18, `fallback` with a hairline edge.
    ///
    /// - Parameters:
    ///   - isInteractive: the glass reacts to touches, which a material cannot.
    ///   - tint: tints the glass (the reader's Translate when on). `nil` for untinted.
    func glassSurface(
        in shape: some Shape, isInteractive: Bool = false, tint: Color? = nil, fallback: GlassFallback = .regular
    ) -> some View {
        modifier(GlassSurface(shape: shape, isInteractive: isInteractive, tint: tint, fallback: fallback))
    }

    /// `.buttonStyle(.glass)`; `.bordered` on iOS 18.
    func glassButtonStyle() -> some View {
        modifier(GlassButtonStyle(isProminent: false))
    }

    /// The primary action: `.buttonStyle(.glassProminent)` in the tint, its label in the
    /// colour that reads on the tint (`\.onTint`: the ground colour on Wall's label-coloured
    /// tint); `.borderedProminent` with the same label on iOS 18.
    func glassProminentButtonStyle() -> some View {
        modifier(GlassButtonStyle(isProminent: true))
    }

    /// Lets this glass shape morph into or out of another with the same `id` in `namespace`,
    /// inside one `GlassGroup` (`glassEffectID`). On iOS 18 the material shapes are matched
    /// with `matchedGeometryEffect` and cross-fade. With Reduce Motion the shapes do not
    /// travel: each fades where it is.
    func glassMorphID(_ id: some Hashable & Sendable, in namespace: Namespace.ID) -> some View {
        modifier(GlassMorph(id: id, namespace: namespace))
    }
}

/// A `GlassEffectContainer`, so neighbouring glass shapes blend and morph; a plain group on
/// iOS 18.
struct GlassGroup<Content: View>: View {
    private let spacing: CGFloat?
    private let content: Content

    init(spacing: CGFloat? = nil, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        if #available(iOS 26, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}

private struct GlassSurface<S: Shape>: ViewModifier {
    let shape: S
    let isInteractive: Bool
    let tint: Color?
    let fallback: GlassFallback

    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.glassEffect(.regular.tint(tint).interactive(isInteractive), in: shape)
        } else {
            // The hairline stands in for glass's lit edge, which keeps the surface visible on
            // backgrounds close to the material's own colour.
            content
                .background {
                    switch fallback {
                    case .regular: shape.fill(.regularMaterial)
                    case .thin: shape.fill(.thinMaterial)
                    }
                    if let tint {
                        shape.fill(tint.opacity(0.35))
                    }
                }
                .overlay { shape.stroke(.quaternary, lineWidth: 1) }
        }
    }
}

private struct GlassButtonStyle: ViewModifier {
    let isProminent: Bool
    @Environment(\.onTint) private var onTint

    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            if isProminent {
                // The style draws its label white, which vanishes on a light tint.
                content.buttonStyle(.glassProminent).foregroundStyle(onTint)
            } else {
                content.buttonStyle(.glass)
            }
        } else if isProminent {
            content.buttonStyle(.borderedProminent).foregroundStyle(onTint)
        } else {
            content.buttonStyle(.bordered)
        }
    }
}

private struct GlassMorph<ID: Hashable & Sendable>: ViewModifier {
    let id: ID
    let namespace: Namespace.ID
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            // The container's morph moves and stretches the glass whatever the setting says;
            // materialising makes each shape appear or dissolve in place instead.
            if reduceMotion {
                content
                    .glassEffectID(id, in: namespace)
                    .glassEffectTransition(.materialize)
            } else {
                content.glassEffectID(id, in: namespace)
            }
        } else if reduceMotion {
            content.transition(.opacity)
        } else {
            content
                .matchedGeometryEffect(id: id, in: namespace)
                .transition(.opacity)
        }
    }
}
