import SwiftUI

// Pieces every step of the setup wizard shares.

/// A step's heading: the step's name as a large title, the sentence under it, and, on the
/// pages' steps, the draft's state so far in the tint.
struct DesignSetupHeading: View {
    let title: String
    let caption: String
    var soFar: String?

    @Environment(\.look) private var look

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.xSmall) {
            Text(title)
                .font(.title.bold())
                .lookTitleDesign()
                .foregroundStyle(look.label)
                .accessibilityAddTraits(.isHeader)
            Text(caption)
                .font(.subheadline)
                .foregroundStyle(look.secondaryLabel)
            if let soFar {
                Text(soFar)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tint)
                    .padding(.top, Tokens.Spacing.xSmall)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Tokens.Spacing.small)
        .padding(.top, Tokens.Spacing.large)
        .padding(.bottom, Tokens.Spacing.medium)
    }
}

/// The wizard's progress: one mark per counted step, those reached in the tint. The step
/// count under the title says the same to VoiceOver.
struct DesignSetupProgress: View {
    let reached: Int
    let total: Int

    @Environment(\.look) private var look
    @Environment(\.lookTint) private var tint
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: Tokens.Spacing.xSmall) {
            ForEach(0..<total, id: \.self) { index in
                Capsule()
                    .fill(index < reached ? tint : look.fill)
                    .frame(height: 4)
            }
        }
        .padding(.horizontal, Tokens.Spacing.xLarge)
        .padding(.vertical, Tokens.Spacing.small)
        .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: reached)
        .accessibilityHidden(true)
    }
}

/// An empty ring, or a filled circle with a check in the tint: the option card's mark, for
/// the wizard's own "Keep what I have" card.
struct DesignSetupRadioMark: View {
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
