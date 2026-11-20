import EhCore
import EhFeatures
import EhModels
import SwiftUI

private typealias Part = L10n.Localizable.Settings.Design.Part

/// The wizard's summary: the draft's state as the title, a sentence on what differs from the
/// nearest preset, three pictures of the draft, and the eight choices as lines, in the tint
/// where they differ from what the app uses now. A tap on a line opens that page's step.
struct DesignSetupSummary: View {
    let model: DesignSetupModel
    let open: (DesignPart) -> Void

    @Environment(\.look) private var look

    var body: some View {
        let draft = model.draft
        VStack(spacing: 0) {
            DesignSetupHeading(title: draft.localizedStateName, caption: draft.localizedSetupSentence)
            DesignSetupPictures(choices: draft)
            DesignSetupLines(model: model, open: open)
                .padding(.top, Tokens.Spacing.large)
            Text(model.hasChanges
                 ? L10n.Localizable.Settings.Design.Setup.nothingYet
                 : L10n.Localizable.Settings.Design.Setup.noChanges)
                .settingsFootnote()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Tokens.Spacing.large)
                .padding(.top, Tokens.Spacing.small)
        }
    }
}

/// The draft's first screen, gallery page and reader, side by side, in the draft's colours.
private struct DesignSetupPictures: View {
    let choices: DesignChoices

    @Environment(\.look) private var look
    private static let size = CGSize(width: 86, height: 137.6)

    var body: some View {
        HStack(alignment: .top, spacing: Tokens.Spacing.medium) {
            picture(.firstScreen(choices), caption: Part.start)
            picture(.gallery(choices), caption: Part.gallery)
            picture(.reader(choices), caption: Part.reader)
        }
        .frame(maxWidth: .infinity)
    }

    private func picture(_ subject: DesignPreview.Subject, caption: String) -> some View {
        VStack(spacing: Tokens.Spacing.xSmall) {
            DesignPreview(subject)
                .frame(width: Self.size.width, height: Self.size.height)
            Text(caption)
                .font(.caption2.weight(.medium))
                .foregroundStyle(look.secondaryLabel)
                .multilineTextAlignment(.center)
                .accessibilityHidden(true)
        }
        .frame(minWidth: Self.size.width)
    }
}

/// One line per page in the wizard's order: the page and the draft's choice, which is in the
/// tint when it differs from the app's current one. A tap opens that page's step.
private struct DesignSetupLines: View {
    let model: DesignSetupModel
    let open: (DesignPart) -> Void

    @Environment(\.look) private var look

    private static let cornerRadius: CGFloat = 20

    var body: some View {
        let draft = model.draft
        VStack(spacing: 0) {
            ForEach(Array(DesignSetupModel.parts.enumerated()), id: \.element) { index, part in
                if index > 0 {
                    Rectangle()
                        .fill(look.separator)
                        .frame(height: 1 / 3)
                        .padding(.leading, Tokens.Spacing.large)
                }
                line(part, choice: draft[part], differs: model.differsFromCurrent(part))
            }
        }
        .background(look.raised, in: .rect(cornerRadius: Self.cornerRadius, style: .continuous))
    }

    private func line(_ part: DesignPart, choice: DesignOption, differs: Bool) -> some View {
        Button {
            open(part)
        } label: {
            HStack(spacing: Tokens.Spacing.small) {
                Text(part.localizedName)
                    .foregroundStyle(look.label)
                Spacer(minLength: Tokens.Spacing.small)
                Text(choice.localizedName)
                    .fontWeight(differs ? .semibold : .regular)
                    .foregroundStyle(differs ? AnyShapeStyle(.tint) : AnyShapeStyle(look.secondaryLabel))
                    .multilineTextAlignment(.trailing)
            }
            .font(.subheadline)
            .padding(.horizontal, Tokens.Spacing.large)
            .frame(minHeight: 40)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}
