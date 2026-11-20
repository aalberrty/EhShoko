import EhCore
import EhFeatures
import EhModels
import SwiftUI

private typealias Start = L10n.Localizable.Settings.Design.Setup.Start

/// The wizard's first step: the stage playing the presets with its three tiles, and "Keep
/// what I have" under them. A tile sets the whole draft to its preset; "Keep what I have" sets
/// it back to the current choices, and the presets take turns on the stage again.
///
/// The stage is the only one on screen and has no glass around it (it brings its own pause
/// button). It pauses itself when it is not seen; the screen says when an alert covers it.
struct DesignSetupStartStep: View {
    let model: DesignSetupModel
    /// An alert is over the wizard.
    let isCovered: Bool

    var body: some View {
        VStack(spacing: 0) {
            DesignSetupHeading(title: Start.title, caption: Start.body)
            // Stays on the selected preset when there is one: coming back to this step, or
            // starting from the offer's choice. With "Keep what I have" the presets take turns.
            PresetStage(selection: selection, staysOnInitialSelection: true, isCovered: isCovered)
                .frame(maxWidth: .infinity)
            DesignSetupKeepCard(current: model.current, isSelected: model.startingPoint == nil) {
                model.selectStartingPoint(nil)
            }
            .padding(.top, Tokens.Spacing.large)
            if model.replacesLaterChoices {
                Text(Start.replace)
                    .settingsFootnote()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Tokens.Spacing.large)
                    .padding(.top, Tokens.Spacing.small)
            }
        }
    }

    private var selection: Binding<DesignStyle?> {
        Binding(get: { model.startingPoint }, set: { model.selectStartingPoint($0) })
    }
}

/// "Keep what I have": a small picture of the current first screen, the current state and a
/// radio mark, drawn like a slim option card.
private struct DesignSetupKeepCard: View {
    let current: DesignChoices
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.look) private var look
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let cornerRadius: CGFloat = 20
    private static let previewWidth: CGFloat = 32

    var body: some View {
        let title = Start.keep
        let summary = current.localizedSummary
        Button(action: action) {
            HStack(spacing: Tokens.Spacing.medium) {
                DesignPreview(.firstScreen(current))
                    .frame(width: Self.previewWidth, height: Self.previewWidth * 1.6)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Tokens.Spacing.xxSmall) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(look.label)
                    Text(summary)
                        .font(.subheadline)
                        .foregroundStyle(look.secondaryLabel)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                RadioMark(isSelected: isSelected)
            }
            .padding(Tokens.Spacing.small)
            .padding(.trailing, Tokens.Spacing.small)
            .background(look.raised, in: .rect(cornerRadius: Self.cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                    .strokeBorder(.tint, lineWidth: 2)
                    .opacity(isSelected ? 1 : 0)
            }
            .contentShape(.rect(cornerRadius: Self.cornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: isSelected)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(summary))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
