import EhCore
import EhFeatures
import EhModels
import SwiftUI

/// The Settings page's Experience card: the preset tiles, Customise and the setup wizard.
struct ExperienceSection: View {
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        Section {
            PresetTiles()
            NavigationLink(value: Route.settings(.design)) {
                SettingsRowLabel(
                    symbol: "slider.horizontal.3", title: L10n.Localizable.Settings.Design.customise,
                    description: settings.designChoices.localizedSummary
                )
            }
            if DesignSetupEntry.isAvailable {
                NavigationLink(value: Route.settings(.designSetup())) {
                    SettingsRowLabel(
                        symbol: "wand.and.stars", title: L10n.Localizable.Settings.Design.setup,
                        description: L10n.Localizable.Settings.Design.Setup.desc
                    )
                }
            }
        } header: {
            Text(L10n.Localizable.Settings.design).settingsSectionHeader()
        }
        .settingsRow()
    }
}

/// Whether the setup wizard can be opened (`Design/Setup/`, routed as `.designSetup` in
/// `SettingsDestination`).
enum DesignSetupEntry {
    static let isAvailable = true
}
