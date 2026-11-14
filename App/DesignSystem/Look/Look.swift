import EhModels
import SwiftUI

/// The app's colours and type: one look for the whole app (`Design/designs/README.md`
/// section 7).
///
/// The shell sets it once, at the root, with `lookEnvironment(_:accent:)`; every view reads
/// `\.look` and takes its tokens from it. Tokens are static tables, so reading one is a
/// `switch`, and colours are dynamic (light, dark, increased contrast), so no view reads
/// `colorScheme` to pick one. A cell may read `\.look`: it changes only when the look does.
nonisolated enum Look: Hashable, Sendable, CaseIterable {
    case shelf, wall, ledger

    init(_ style: DesignStyle) {
        switch style {
        case .shelf: self = .shelf
        case .wall: self = .wall
        case .ledger: self = .ledger
        }
    }
}

extension EnvironmentValues {
    /// The look the app wears. Set by the shell; the default is Shelf, the default preset.
    @Entry var look: Look = .shelf
    /// The colour of text and symbols drawn on a fill of the tint (the prominent pill, a
    /// selected chip). Set with the tint by `lookEnvironment(_:accent:)`.
    @Entry var onTint: Color = .white
}

extension View {
    /// Puts `look` and the tint it gives `accent` into the environment. The shell calls this
    /// once at the root, and again on a presented root that does not inherit it.
    func lookEnvironment(_ look: Look, accent: RGBColor) -> some View {
        modifier(LookEnvironment(look: look, accent: accent))
    }
}

private struct LookEnvironment: ViewModifier {
    let look: Look
    let accent: RGBColor

    func body(content: Content) -> some View {
        let tint = look.tint(for: accent)
        content
            .environment(\.look, look)
            .environment(\.onTint, tint.onTint)
            .tint(tint.tint)
    }
}
