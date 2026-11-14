import EhCore
import EhFeatures
import SwiftUI

/// Settings › Laboratory (legacy `LaboratorySettingView`).
struct LaboratorySettingsScreen: View {
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        // `AppModel` applies the setting to the transport whenever it changes.
        @Bindable var settings = settings
        Form {
            Section {
                Toggle(isOn: $settings.bypassesSNIFiltering) {
                    Label {
                        Text(L10n.Localizable.LaboratorySettingView.Title.bypassesSNIFiltering)
                    } icon: {
                        SettingsIcon(
                            systemImage: "theatermasks.fill",
                            color: settings.bypassesSNIFiltering ? .purple : .gray
                        )
                    }
                }
                .tint(.purple)
            }
            #if DEBUG
            // Development aids: the reader engine with synthetic pages, and a list of synthetic
            // galleries with a scripted scroll for measuring list views.
            Section("Debug") {
                ReaderHarnessLauncher()
                ListHarnessLauncher()
            }
            #endif
        }
        .navigationTitle(L10n.Localizable.LaboratorySettingView.Title.laboratory)
        .animation(.default, value: settings.bypassesSNIFiltering)
        .sensoryFeedback(.impact(flexibility: .soft), trigger: settings.bypassesSNIFiltering)
    }
}

#Preview {
    SettingsPreview { LaboratorySettingsScreen() }
}
