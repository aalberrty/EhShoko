import SwiftUI

// The grouped form of the shared sheets (Settings, Filters, quick searches) on the look's
// tokens: the look's surface as the ground, its raised colour for the cards, its separator,
// its labels. The sheets are the system's (`Design/designs/README.md` section 13): nothing here
// sets `presentationBackground`, and no row is glass.

extension View {
    /// The form's ground: the look's surface in place of the system's grouped background.
    /// Settings and Filters pass `.compact`, the drawings' gaps between their cards.
    func lookFormStyle(sectionSpacing: ListSectionSpacing = .default) -> some View {
        modifier(LookFormGround(sectionSpacing: sectionSpacing))
    }

    /// One row of a card: the look's raised colour and separator, and the text colour `text`
    /// says.
    func lookFormRow(_ text: LookFormRowText = .label) -> some View {
        modifier(LookFormRow(text: text))
    }

    /// A section's heading: small, semibold, uppercase, in the look's secondary colour.
    func lookFormHeader() -> some View {
        modifier(LookFormHeader())
    }
}

/// The text colour of a form's row.
enum LookFormRowText {
    /// The look's label colour, or its tertiary colour while the row is disabled.
    case label
    /// The look's label colour even while disabled: for a navigation link, which the system
    /// dims itself, so that it is dimmed once.
    case labelDimmedBySystem
    /// Left to the control, so a button keeps its tint or its red; a row that draws its own
    /// text takes it from the look.
    case control
}

private struct LookFormGround: ViewModifier {
    let sectionSpacing: ListSectionSpacing

    @Environment(\.look) private var look

    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background(look.surface)
            .listSectionSpacing(sectionSpacing)
    }
}

private struct LookFormRow: ViewModifier {
    let text: LookFormRowText

    @Environment(\.look) private var look
    @Environment(\.isEnabled) private var isEnabled

    func body(content: Content) -> some View {
        switch text {
        case .label, .labelDimmedBySystem:
            content
                .foregroundStyle(isEnabled || text == .labelDimmedBySystem ? look.label : look.tertiaryLabel)
                .modifier(LookFormRowGround())
        case .control:
            content.modifier(LookFormRowGround())
        }
    }
}

private struct LookFormRowGround: ViewModifier {
    @Environment(\.look) private var look

    func body(content: Content) -> some View {
        content
            .listRowBackground(look.raised)
            .listRowSeparatorTint(look.separator)
    }
}

private struct LookFormHeader: ViewModifier {
    @Environment(\.look) private var look

    func body(content: Content) -> some View {
        content
            .font(.footnote.weight(.semibold))
            .textCase(.uppercase)
            .foregroundStyle(look.secondaryLabel)
    }
}
