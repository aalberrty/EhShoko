import EhCore
import EhFeatures
import EhModels
import SwiftUI

/// A page's step: its name, its caption, the draft's state so far, and one option card per
/// choice, the draft's selected and the app's current one tagged "Current". The cards are the
/// options screen's; their previews are drawn in the draft's colours, which step 2 chose.
struct DesignSetupPartStep: View {
    let model: DesignSetupModel
    let part: DesignPart
    /// Called after a card was chosen, for the selection haptic.
    let chose: () -> Void

    var body: some View {
        let draft = model.draft
        let current = model.current
        VStack(spacing: Tokens.Spacing.medium) {
            DesignSetupHeading(
                title: part.localizedName,
                caption: part.localizedCaption,
                soFar: L10n.Localizable.Settings.Design.Setup.soFar(draft.localizedSoFar)
            )
            ForEach(part.options, id: \.self) { option in
                DesignOptionCard(
                    part: part, option: option, isSelected: draft[part] == option,
                    look: draft.look, isCurrent: current[part] == option, previewWidth: 84
                ) {
                    model.select(option, for: part)
                    chose()
                }
            }
        }
    }
}
