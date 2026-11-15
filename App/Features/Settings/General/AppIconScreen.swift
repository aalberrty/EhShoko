import EhCore
import EhFeatures
import EhModels
import SwiftUI
import UIKit

/// Settings › General › App icon (legacy `AppIconView`). General hides its row while the app
/// has one icon (`AppIconModel.offersChoice`).
struct AppIconScreen: View {
    @State private var model = AppIconModel()
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        Form {
            Section {
                ForEach(AppIconType.allCases) { icon in
                    Button {
                        Task { await model.select(icon) }
                    } label: {
                        AppIconRow(icon: icon, isSelected: icon == settings.appIconType)
                    }
                    .buttonStyle(.plain)
                }
            }
            .settingsRow()
        }
        .settingsFormStyle()
        .navigationTitle(L10n.Localizable.AppIconView.Title.appIcon)
        .sensoryFeedback(.selection, trigger: settings.appIconType)
        .task { model.syncWithSystem() }
    }
}

private struct AppIconRow: View {
    let icon: AppIconType
    let isSelected: Bool

    @ScaledMetric(relativeTo: .body) private var size: CGFloat = 60

    var body: some View {
        HStack(spacing: Tokens.Spacing.xLarge) {
            // An icon set compiled into the asset catalog loads by name like an image.
            if let image = UIImage(named: icon.iconSetName) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size, height: size)
                    .clipShape(.rect(cornerRadius: size / 4, style: .continuous))
                    .accessibilityHidden(true)
            }
            Text(icon.localizedName)
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .imageScale(.large)
                .foregroundStyle(.tint)
                .opacity(isSelected ? 1 : 0)
                .accessibilityHidden(true)
        }
        .padding(.vertical, Tokens.Spacing.small)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#Preview {
    SettingsPreview { AppIconScreen() }
}
