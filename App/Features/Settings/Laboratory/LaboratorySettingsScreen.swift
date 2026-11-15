import EhCore
import EhFeatures
import SwiftUI

/// Settings › Laboratory (legacy `LaboratorySettingView`), and in debug builds the harnesses.
struct LaboratorySettingsScreen: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(\.look) private var look

    var body: some View {
        // `AppModel` applies the setting to the transport whenever it changes.
        @Bindable var settings = settings
        Form {
            Section {
                Toggle(isOn: $settings.bypassesSNIFiltering) {
                    Label {
                        Text(L10n.Localizable.LaboratorySettingView.Title.bypassesSNIFiltering)
                            .foregroundStyle(look.label)
                    } icon: {
                        Image(systemName: "theatermasks")
                            .foregroundStyle(settings.bypassesSNIFiltering ? AnyShapeStyle(.tint) : AnyShapeStyle(look.secondaryLabel))
                            .accessibilityHidden(true)
                    }
                }
            }
            .settingsRow()
            #if DEBUG
            // Development aids: the reader engine with synthetic pages; synthetic galleries with a
            // scripted scroll for measuring lists; one part of the selectable designs in each of its
            // surroundings; every design preview; the look's shared pieces.
            Section {
                ReaderHarnessLauncher()
                ListHarnessLauncher()
                PartHarnessLauncher()
                HarnessSheetLauncher(title: "Preview gallery") { PreviewHarnessView() }
                HarnessSheetLauncher(title: "Look harness") { LookHarnessView() }
            } header: {
                Text(verbatim: "Debug").settingsSectionHeader()
            }
            .settingsRow()
            #endif
        }
        .settingsFormStyle()
        .navigationTitle(L10n.Localizable.LaboratorySettingView.Title.laboratory)
        .animation(.default, value: settings.bypassesSNIFiltering)
        .sensoryFeedback(.impact(flexibility: .soft), trigger: settings.bypassesSNIFiltering)
    }
}

#if DEBUG
/// A harness built to be the whole app, opened in a sheet so that a swipe closes it.
private struct HarnessSheetLauncher<Harness: View>: View {
    let title: String
    @ViewBuilder let harness: () -> Harness
    @State private var isPresented = false

    var body: some View {
        Button { isPresented = true } label: { Text(verbatim: title) }
            .sheet(isPresented: $isPresented) { harness() }
    }
}
#endif

#Preview {
    SettingsPreview { LaboratorySettingsScreen() }
}
