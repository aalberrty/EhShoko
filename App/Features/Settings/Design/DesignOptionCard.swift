import EhModels
import SwiftUI

/// One choice of one page as a full-width card: its preview leading, then its name and
/// description, and a radio mark trailing. The selected card has a ring in the tint and a
/// filled mark. The options screen and the setup wizard both use it.
///
/// It draws its own card (the look's raised colour), so it can sit in a list row with a clear
/// background or in a plain stack. To VoiceOver it is one button that reads the name and the
/// description, with the selected trait. A tap calls `action`; the card decides nothing.
struct DesignOptionCard: View {
    let part: DesignPart
    let option: DesignOption
    let isSelected: Bool
    /// The look the preview is drawn in: `nil` for the app's; the wizard passes its draft's.
    var look: DesignStyle?
    /// The wizard marks the option the app uses now with a small "Current" tag.
    var isCurrent = false
    /// The preview's width; its height is 1.6 times that. 95 to 105 on the options screen,
    /// 84 in the wizard.
    var previewWidth: CGFloat = 100
    let action: () -> Void

    @Environment(\.look) private var appLook
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let cornerRadius: CGFloat = 20

    var body: some View {
        Button(action: action) {
            HStack(spacing: Tokens.Spacing.large) {
                DesignPreview(.option(part, option), look: look)
                    .frame(width: previewWidth, height: previewWidth * 1.6)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Tokens.Spacing.xSmall) {
                    Text(option.localizedName)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(appLook.label)
                    if let description {
                        Text(description)
                            .font(.subheadline)
                            .foregroundStyle(appLook.secondaryLabel)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if isCurrent {
                        CurrentTag()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                RadioMark(isSelected: isSelected)
            }
            .padding(Tokens.Spacing.small)
            .padding(.trailing, Tokens.Spacing.small)
            .background(appLook.raised, in: .rect(cornerRadius: Self.cornerRadius, style: .continuous))
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
        .accessibilityLabel(Text(option.localizedName))
        .accessibilityValue(Text(accessibilityValue))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var description: String? {
        part.localizedDescription(of: option)
    }

    private var accessibilityValue: String {
        [description, isCurrent ? L10n.Localizable.Settings.Design.Setup.current : nil]
            .compactMap(\.self).joined(separator: ", ")
    }
}

/// An empty ring, or a filled circle with a check in the tint.
private struct RadioMark: View {
    let isSelected: Bool

    @Environment(\.look) private var look
    @Environment(\.onTint) private var onTint

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(look.tertiaryLabel, lineWidth: 1.5)
                .opacity(isSelected ? 0 : 1)
            Image(systemName: "checkmark.circle.fill")
                .resizable()
                .symbolRenderingMode(.palette)
                .foregroundStyle(onTint, .tint)
                .opacity(isSelected ? 1 : 0)
        }
        .frame(width: 24, height: 24)
        .accessibilityHidden(true)
    }
}

/// "Current", in the wizard, on the option the app uses now.
private struct CurrentTag: View {
    @Environment(\.look) private var look

    var body: some View {
        Text(L10n.Localizable.Settings.Design.Setup.current)
            .font(.caption.weight(.semibold))
            .foregroundStyle(look.secondaryLabel)
            .padding(.horizontal, Tokens.Spacing.small)
            .padding(.vertical, Tokens.Spacing.xxSmall)
            .background(look.fill2, in: .capsule)
    }
}
