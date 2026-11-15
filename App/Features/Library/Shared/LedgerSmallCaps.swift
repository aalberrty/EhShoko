import SwiftUI

extension View {
    /// Ledger's small capitals, used across its parts (the Index, the gallery page, search):
    /// uppercase, 11 pt bold, tracked 0.9, in the secondary colour unless a colour is given,
    /// under every look. A layout detail, not the look's section heading. Uppercase is a text
    /// case, so VoiceOver reads the original string.
    func ledgerSmallCaps(_ color: Color? = nil) -> some View {
        modifier(LedgerSmallCaps(color: color))
    }
}

private struct LedgerSmallCaps: ViewModifier {
    let color: Color?
    @Environment(\.look) private var look

    func body(content: Content) -> some View {
        content
            .font(.caption2.bold())
            .tracking(0.9)
            .textCase(.uppercase)
            .foregroundStyle(color ?? look.secondaryLabel)
    }
}
