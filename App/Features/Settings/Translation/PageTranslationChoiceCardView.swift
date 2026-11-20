import EhFeatures
import EhModels
import SwiftUI

/// One choice on a selection screen: a radio mark, the model's name, where it stands ("Default ·
/// Installed", "Needs 2.5 GB"), and every figure measured for it under the heading of what it
/// was measured on, a caveat under the figure that needs one.
///
/// Content, not a control layer: the look's raised colour, no glass, no shadow. It takes a value
/// and reads no store. To VoiceOver the head is the button, with the selected trait, and each
/// figure is an element of its own that names what it was measured on.
struct PageTranslationChoiceCardView: View {
    let card: PageTranslationChoiceCard
    let choose: () -> Void

    @Environment(\.look) private var look
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let cornerRadius: CGFloat = 20
    /// The radio mark's width and the gap after it: figures line up under the name.
    private static let markInset: CGFloat = 24 + Tokens.Spacing.medium

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.medium) {
            head
            ForEach(Array(card.figureGroups.enumerated()), id: \.offset) { _, group in
                FigureGroupView(group: group)
            }
            .padding(.leading, Self.markInset)
        }
        .padding(Tokens.Spacing.large)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(look.raised, in: .rect(cornerRadius: Self.cornerRadius, style: .continuous))
        .overlay { ring }
        .contentShape(.rect(cornerRadius: Self.cornerRadius, style: .continuous))
        .onTapGesture {
            if card.canBeChosen { choose() }
        }
        .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: card.isSelected)
        .accessibilityElement(children: .contain)
    }

    private var head: some View {
        HStack(alignment: .top, spacing: Tokens.Spacing.medium) {
            RadioMark(isSelected: card.isSelected)
                .opacity(card.canBeChosen ? 1 : 0.4)
            VStack(alignment: .leading, spacing: Tokens.Spacing.xxSmall) {
                Text(verbatim: card.choice.displayName)
                    .font(.headline)
                    .foregroundStyle(card.canBeChosen ? look.label : look.secondaryLabel)
                Text(card.statusText)
                    .font(.subheadline)
                    .foregroundStyle(look.secondaryLabel)
                if let progress = card.progress {
                    ProgressView(value: progress.fraction)
                        .padding(.vertical, Tokens.Spacing.xxSmall)
                }
                if let summary = card.choice.summary {
                    Text(summary)
                        .font(.subheadline)
                        .foregroundStyle(look.secondaryLabel)
                }
                // Only where the licence is the reason: a model the project may pass on is
                // missing only because no public store exists yet.
                if card.availability == .notOffered, card.isPrivateOnly {
                    Text(L10n.Localizable.Settings.Translation.NotPublic.why)
                        .font(.footnote)
                        .foregroundStyle(look.secondaryLabel)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(headTraits)
        .accessibilityAction {
            if card.canBeChosen { choose() }
        }
    }

    private var headTraits: AccessibilityTraits {
        var traits: AccessibilityTraits = card.canBeChosen ? .isButton : []
        if card.isSelected { traits.formUnion(.isSelected) }
        return traits
    }

    /// The tint ring of the choice in use; dashed for one that applies once installed.
    @ViewBuilder
    private var ring: some View {
        let shape = RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
        if card.isSelected {
            shape.strokeBorder(.tint, lineWidth: 2)
        } else if card.isPending {
            shape.strokeBorder(.tint, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
        }
    }
}

/// The figures measured on one thing, under its heading.
private struct FigureGroupView: View {
    let group: MeasuredFigureGroup

    @Environment(\.look) private var look

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.xSmall) {
            Text(group.basis.heading)
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(look.secondaryLabel)
                // Each figure says what it was measured on.
                .accessibilityHidden(true)
            ForEach(Array(group.figures.enumerated()), id: \.offset) { _, figure in
                FigureRow(figure: figure)
            }
        }
    }
}

/// One figure: its label leading, its value trailing, and the caveat it carries under it. At
/// accessibility sizes the value goes under the label, so nothing is cut.
private struct FigureRow: View {
    let figure: MeasuredFigure

    @Environment(\.look) private var look
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let stacked = typeSize.isAccessibilitySize
        let layout = stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Tokens.Spacing.xxSmall))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: Tokens.Spacing.medium))
        VStack(alignment: .leading, spacing: Tokens.Spacing.xxSmall) {
            layout {
                Text(figure.kind.label)
                    .foregroundStyle(look.label)
                    .frame(maxWidth: stacked ? nil : .infinity, alignment: .leading)
                Text(figure.value.text)
                    .monospacedDigit()
                    .foregroundStyle(figure.value == .notMeasured ? look.tertiaryLabel : look.label)
                    .multilineTextAlignment(stacked ? .leading : .trailing)
            }
            .font(.subheadline)
            if let note = figure.note {
                Text(note.text)
                    .font(.footnote)
                    .foregroundStyle(look.secondaryLabel)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(figure.kind.label), \(figure.basis.heading)"))
        .accessibilityValue(Text(verbatim: [figure.value.text, figure.note?.text].compactMap(\.self).joined(separator: ", ")))
    }
}
