import EhFeatures
import SwiftUI

/// "Translate drawn sound effects", under the four models: one switch, off by default. On,
/// every box the detector finds is read, translated, erased and lettered, sound effects drawn
/// on the artwork too. With a detector that does not tell sound effects from other text
/// (ogkalu v4-s) it changes nothing, so the row is disabled and says why; what it was set to
/// is kept for another detector.
struct PageTranslationSoundEffectsSection: View {
    @Bindable var model: PageTranslationSettingsModel

    @Environment(\.look) private var look

    private typealias Strings = L10n.Localizable.Settings.Translation

    var body: some View {
        let isAvailable = model.soundEffectsCanBeTranslated
        Section {
            Toggle(isOn: $model.translatesSoundEffects) {
                VStack(alignment: .leading, spacing: Tokens.Spacing.xxSmall) {
                    Text(Strings.soundEffects)
                        .foregroundStyle(isAvailable ? look.label : look.tertiaryLabel)
                    if !isAvailable {
                        Text(Strings.SoundEffects.unavailable(model.current(.detector).displayName))
                            .font(.footnote)
                            .foregroundStyle(look.secondaryLabel)
                    }
                }
            }
            .disabled(!isAvailable)
        } footer: {
            Text(Strings.SoundEffects.footer).settingsFootnote()
        }
        .settingsRow()
    }
}
