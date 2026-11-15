import EhFeatures
import EhModels
import SwiftUI

/// Maps a `SettingsRoute` to its screen. Every screen takes the tint the shell set from the
/// look and the accent.
struct SettingsDestination: View {
    let route: SettingsRoute

    var body: some View {
        switch route {
        case .account: AccountSettingScreen()
        case .login: LoginScreen()
        case .ehSetting: EhSettingScreen()
        case .general: GeneralSettingsScreen()
        case .appIcon: AppIconScreen()
        case .design: DesignScreen()
        case .designPart(let part): DesignOptionsScreen(part: part)
        // The setup wizard's screen goes here when it exists (`DesignSetupEntry`).
        case .designSetup: EmptyView()
        case .reading: ReadingSettingsScreen()
        case .laboratory: LaboratorySettingsScreen()
        case .logs: LogsScreen()
        case .log(let file): LogDetailScreen(file: file)
        case .about: AboutScreen()
        }
    }
}
