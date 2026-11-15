import EhFeatures
import EhModels
import SwiftUI

/// The Settings page, the same for every design (`settings.md`): Shelf's layout with Wall's
/// icons and descriptions. The account card, Experience, then one row per settings screen.
///
/// It is the root of the Settings sheet's stack; the shell presents the sheet and gives it
/// its close button.
struct SettingsScreen: View {
    var body: some View {
        List {
            SettingsAccountSection()
            ExperienceSection()
            SettingsScreensSection()
        }
        .settingsFormStyle()
        .navigationTitle(L10n.Localizable.SettingView.Title.setting)
        .navigationBarTitleDisplayMode(.inline)
        .presentationDragIndicator(.visible)
        .presentationSizing(.form)
        #if DEBUG
        .settingsProbe(isPage: true)
        #endif
    }
}

/// General, Reading, Laboratory and About. Translation's row goes between Reading and
/// Laboratory once reader translation exists.
private struct SettingsScreensSection: View {
    var body: some View {
        Section {
            row(.general, symbol: "gearshape", description: L10n.Localizable.Settings.Row.General.desc)
            row(.reading, symbol: "book", description: L10n.Localizable.Settings.Row.Reading.desc)
            row(.laboratory, symbol: "flask", description: L10n.Localizable.Settings.Row.Laboratory.desc)
            row(.about, symbol: "info.circle", description: Self.version)
        }
        .settingsRow()
    }

    private func row(_ route: SettingsRoute, symbol: String, description: String) -> some View {
        NavigationLink(value: Route.settings(route)) {
            SettingsRowLabel(symbol: symbol, title: route.rootTitle, description: description)
        }
    }

    /// "Version 3.0 (158)".
    private static let version: String = {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? ""
        let build = info?["CFBundleVersion"] as? String ?? ""
        return L10n.Localizable.Settings.Row.About.desc(version, build)
    }()
}

private extension SettingsRoute {
    var rootTitle: String {
        typealias Value = L10n.Localizable.Enum.SettingStateRoute.Value
        return switch self {
        case .general: Value.general
        case .reading: Value.reading
        case .laboratory: Value.laboratory
        case .about: Value.about
        default: ""
        }
    }
}

#Preview {
    SettingsPreview { SettingsScreen() }
}
