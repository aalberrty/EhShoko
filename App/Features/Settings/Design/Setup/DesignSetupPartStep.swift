import EhCore
import EhFeatures
import EhModels
import SwiftUI

/// A page's step: its name, its caption, the draft's state so far, and one option card per
/// choice, the draft's selected and the app's current one tagged "Current". The cards are the
/// options screen's; their previews are drawn in the draft's colours, which step 2 chose.
///
/// On an iPad at the standard text sizes (its form sheet) the cards' previews
/// shrink until every card fits the step's visible height, so no card waits under the bottom
/// toolbar; elsewhere they keep the phone's size and the step may scroll.
struct DesignSetupPartStep: View {
    let model: DesignSetupModel
    let part: DesignPart
    /// The height of the step's scroll view inside its bars and insets.
    let visibleHeight: CGFloat
    /// Called after a card was chosen, for the selection haptic.
    let chose: () -> Void

    @State private var headingHeight: CGFloat = 0
    @Environment(\.dynamicTypeSize) private var typeSize

    static let spacing = Tokens.Spacing.medium
    /// The preview's width on the phone, and the most it takes anywhere.
    static let previewWidth: CGFloat = 84
    /// The least it shrinks to: as tall as a card's name, description and tag.
    static let leastPreviewWidth: CGFloat = 52

    var body: some View {
        let draft = model.draft
        let current = model.current
        VStack(spacing: Self.spacing) {
            DesignSetupHeading(
                title: part.localizedName,
                caption: part.localizedCaption,
                soFar: L10n.Localizable.Settings.Design.Setup.soFar(draft.localizedSoFar)
            )
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { headingHeight = $0 }
            ForEach(part.options, id: \.self) { option in
                DesignOptionCard(
                    part: part, option: option, isSelected: draft[part] == option,
                    look: draft.look, isCurrent: current[part] == option, previewWidth: previewWidth
                ) {
                    model.select(option, for: part)
                    chose()
                }
            }
        }
    }

    private var previewWidth: CGFloat {
        // The form sheet reports a compact width, so the device is what tells it from a phone.
        guard UIDevice.current.userInterfaceIdiom == .pad, !typeSize.isAccessibilitySize, visibleHeight > 0, headingHeight > 0 else {
            return Self.previewWidth
        }
        let count = CGFloat(part.options.count)
        let cards = visibleHeight - headingHeight - Self.spacing * count - DesignSetupScreen.bottomPadding
        let preview = (cards / count - DesignOptionCard.verticalPadding) / DesignOptionCard.previewAspect
        return min(max(preview.rounded(.down), Self.leastPreviewWidth), Self.previewWidth)
    }
}
