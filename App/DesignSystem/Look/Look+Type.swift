import SwiftUI

// The type tokens of `Design/designs/README.md` section 7. Every text uses a Dynamic Type
// style; the point sizes in the design files are that style's default size.

nonisolated extension Look {
    /// The face of gallery titles: New York under Ledger, which falls back to the system face
    /// for CJK glyphs.
    var titleDesign: Font.Design {
        switch self {
        case .shelf, .wall: .default
        case .ledger: .serif
        }
    }

    /// The face of search syntax and quick searches.
    var syntaxDesign: Font.Design {
        switch self {
        case .shelf: .default
        case .wall, .ledger: .monospaced
        }
    }

    /// A section's heading: Shelf 22 pt bold in sentence case; Wall 13 pt bold, uppercase,
    /// tracked 0.5; Ledger's small capitals, 11 pt bold, uppercase, tracked 0.9.
    var sectionHeader: SectionHeaderStyle {
        switch self {
        case .shelf: SectionHeaderStyle(font: .title2.bold(), isUppercase: false, tracking: 0, isSecondary: false)
        case .wall: SectionHeaderStyle(font: .footnote.bold(), isUppercase: true, tracking: 0.5, isSecondary: true)
        case .ledger: SectionHeaderStyle(font: .caption2.bold(), isUppercase: true, tracking: 0.9, isSecondary: true)
        }
    }
}

nonisolated struct SectionHeaderStyle: Equatable, Sendable {
    let font: Font
    let isUppercase: Bool
    let tracking: CGFloat
    /// Wall's and Ledger's headings are secondary; Shelf's are the label colour.
    let isSecondary: Bool
}

extension View {
    /// Sets the view's text as the look's section heading. Uppercase is a text case, so
    /// VoiceOver reads the original string.
    func lookSectionHeader() -> some View {
        modifier(LookSectionHeader())
    }

    /// Sets the view's text in the look's title face (New York under Ledger).
    func lookTitleDesign() -> some View {
        modifier(LookFontDesign(kind: .title))
    }

    /// Sets the view's text in the look's face for search syntax.
    func lookSyntaxDesign() -> some View {
        modifier(LookFontDesign(kind: .syntax))
    }
}

private struct LookSectionHeader: ViewModifier {
    @Environment(\.look) private var look

    func body(content: Content) -> some View {
        let style = look.sectionHeader
        content
            .font(style.font)
            .tracking(style.tracking)
            .textCase(style.isUppercase ? .uppercase : nil)
            .foregroundStyle(style.isSecondary ? look.secondaryLabel : look.label)
            .accessibilityAddTraits(.isHeader)
    }
}

private struct LookFontDesign: ViewModifier {
    enum Kind { case title, syntax }

    let kind: Kind
    @Environment(\.look) private var look

    func body(content: Content) -> some View {
        content.fontDesign(kind == .title ? look.titleDesign : look.syntaxDesign)
    }
}
