import EhCore
import EhFeatures
import EhModels
import SwiftUI

/// Settings › Experience (`settings.md`, "The Experience screen"): the current choices with
/// three pictures of them and the presets as chips; Look (colours and type, theme, accent);
/// and one row per page, each pushing that page's options.
///
/// Every change applies at once, behind the sheet. The screen is still: its previews draw
/// again only when a choice, the look, the theme or the accent changes.
struct DesignScreen: View {
    var body: some View {
        List {
            DesignSummaryCard()
            DesignLookSection()
            DesignPagesSection()
        }
        .settingsFormStyle()
        .navigationTitle(L10n.Localizable.Settings.design)
        .navigationBarTitleDisplayMode(.inline)
        #if DEBUG
        .settingsProbe()
        #endif
    }
}

/// "Your experience": the state, what it is, three pictures of it, and the chips that apply a
/// preset or bring the remembered mix back.
private struct DesignSummaryCard: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(\.look) private var look

    var body: some View {
        let choices = settings.designChoices
        Section {
            VStack(alignment: .leading, spacing: Tokens.Spacing.medium) {
                VStack(alignment: .leading, spacing: Tokens.Spacing.xxSmall) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(choices.localizedStateName)
                            .font(.title2.bold())
                            .lookTitleDesign()
                            .foregroundStyle(look.label)
                        Spacer(minLength: Tokens.Spacing.small)
                        Text(choices.preset == nil ? L10n.Localizable.Settings.Design.ownMix : L10n.Localizable.Settings.Design.preset)
                            .font(.footnote)
                            .foregroundStyle(look.secondaryLabel)
                    }
                    Text(choices.localizedSummary)
                        .font(.footnote)
                        .foregroundStyle(look.secondaryLabel)
                }
                .accessibilityElement(children: .combine)
                DesignPictures(choices: choices)
                DesignPresetChips(choices: choices, remembered: settings.designCustom)
            }
            .padding(.vertical, Tokens.Spacing.small)
        }
        .settingsRow()
    }
}

/// The first screen, the gallery page and the reader of a set of choices, side by side.
private struct DesignPictures: View {
    let choices: DesignChoices

    @Environment(\.look) private var look
    private static let size = CGSize(width: 66, height: 106)

    var body: some View {
        HStack(alignment: .top, spacing: Tokens.Spacing.medium) {
            picture(.firstScreen(choices), caption: L10n.Localizable.Settings.Design.Part.start)
            picture(.gallery(choices), caption: L10n.Localizable.Settings.Design.Part.gallery)
            picture(.reader(choices), caption: L10n.Localizable.Settings.Design.Part.reader)
        }
        .frame(maxWidth: .infinity)
    }

    private func picture(_ subject: DesignPreview.Subject, caption: String) -> some View {
        VStack(spacing: Tokens.Spacing.xSmall) {
            DesignPreview(subject)
                .frame(width: Self.size.width, height: Self.size.height)
            Text(caption)
                .font(.caption2)
                // A caption under a picture of fixed width: beyond this size its words break
                // in the middle. The row above says the same in full.
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .foregroundStyle(look.secondaryLabel)
                .multilineTextAlignment(.center)
                .accessibilityHidden(true)
        }
        .frame(minWidth: Self.size.width)
    }
}

/// Shelf, Wall, Ledger and, when a mix is current or remembered, Custom. The current preset is
/// filled with the tint; Custom is outlined in it. A tap applies at once.
private struct DesignPresetChips: View {
    let choices: DesignChoices
    let remembered: DesignChoices?

    @Environment(SettingsStore.self) private var settings
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var taps = 0

    var body: some View {
        let preset = choices.preset
        let showsCustom = preset == nil || remembered != nil
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(FlowLayout(spacing: Tokens.Spacing.small))
            : AnyLayout(HStackLayout(spacing: Tokens.Spacing.small))
        layout {
            ForEach(DesignStyle.allCases, id: \.self) { style in
                DesignChip(title: style.localizedName, style: style == preset ? .filled : .plain) {
                    taps += 1
                    settings.applyDesignPreset(style)
                }
            }
            if showsCustom {
                DesignChip(title: L10n.Localizable.Settings.Design.custom, style: .outlined, isSelected: preset == nil) {
                    taps += 1
                    settings.restoreCustomDesign()
                }
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: taps)
    }
}

private struct DesignChip: View {
    enum Style { case plain, filled, outlined }

    let title: String
    let style: Style
    var isSelected: Bool?
    let action: () -> Void

    @Environment(\.look) private var look
    @Environment(\.onTint) private var onTint

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(foreground)
                .padding(.horizontal, Tokens.Spacing.medium)
                .padding(.vertical, Tokens.Spacing.small)
                .frame(maxWidth: .infinity, minHeight: 34)
                .background { background }
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits((isSelected ?? (style == .filled)) ? .isSelected : [])
    }

    private var foreground: AnyShapeStyle {
        switch style {
        case .plain: AnyShapeStyle(look.label)
        case .filled: AnyShapeStyle(onTint)
        case .outlined: AnyShapeStyle(.tint)
        }
    }

    @ViewBuilder private var background: some View {
        switch style {
        case .plain: Capsule().fill(look.fill2)
        case .filled: Capsule().fill(.tint)
        case .outlined: Capsule().strokeBorder(.tint, lineWidth: 1.5)
        }
    }
}
