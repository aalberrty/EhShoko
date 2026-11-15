import EhCore
import EhFeatures
import SwiftUI

/// The first section of the site's account settings: My tags and the daily reward, which
/// v3 had on its Account screen.
struct SiteAccountSection: View {
    @State private var model = AccountSettingModel()
    @Environment(SettingsStore.self) private var settings
    @Environment(\.look) private var look

    var body: some View {
        @Bindable var settings = settings
        Section {
            if model.isTagsManagementAvailable {
                Button {
                    model.presentTagsManagement()
                } label: {
                    Text(L10n.Localizable.AccountSettingView.Button.tagsManagement).foregroundStyle(look.label)
                }
                .disclosureIndicator()
            }
            Toggle(L10n.Localizable.AccountSettingView.Title.showsNewDawnGreeting, isOn: $settings.showsNewDawnGreeting)
        }
        .settingsRow()
        .sheet(item: $model.destination) { destination in
            switch destination {
            case .webView(let url):
                AccountWebView(url: url)
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: model.destination) { _, new in new != nil }
    }
}
