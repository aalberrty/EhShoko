import SwiftUI

// The Filters sheet's grouped form on the look's tokens: the look's surface as the ground, its
// raised colour for the cards, its separator, its labels. The sheet is the system's
// (`Design/designs/README.md` section 13): nothing here sets `presentationBackground`, and no
// row is glass.

extension View {
    /// The form's ground: the look's surface in place of the system's grouped background.
    func filtersFormStyle() -> some View {
        modifier(FiltersFormStyle())
    }

    /// One row of a card: the look's raised colour and separator, the label in the look's label
    /// colour, or its tertiary colour while the row is disabled. A navigation link is dimmed by
    /// the system when disabled, so it passes `dimsWhenDisabled: false` to be dimmed once.
    func filtersRow(dimsWhenDisabled: Bool = true) -> some View {
        modifier(FiltersRowStyle(dimsWhenDisabled: dimsWhenDisabled))
    }

    /// A section's heading: small, semibold, uppercase, in the look's secondary colour.
    func filtersSectionHeader() -> some View {
        modifier(FiltersSectionHeader())
    }
}

private struct FiltersFormStyle: ViewModifier {
    @Environment(\.look) private var look

    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background(look.surface)
            // The drawing's gaps between the set, the tiles and the card.
            .listSectionSpacing(.compact)
    }
}

private struct FiltersRowStyle: ViewModifier {
    let dimsWhenDisabled: Bool

    @Environment(\.look) private var look
    @Environment(\.isEnabled) private var isEnabled

    func body(content: Content) -> some View {
        content
            .foregroundStyle(isEnabled || !dimsWhenDisabled ? look.label : look.tertiaryLabel)
            .listRowBackground(look.raised)
            .listRowSeparatorTint(look.separator)
    }
}

private struct FiltersSectionHeader: ViewModifier {
    @Environment(\.look) private var look

    func body(content: Content) -> some View {
        content
            .font(.footnote.weight(.semibold))
            .textCase(.uppercase)
            .foregroundStyle(look.secondaryLabel)
    }
}
