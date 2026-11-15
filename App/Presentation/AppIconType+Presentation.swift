import EhModels

extension AppIconType {
    var localizedName: String {
        switch self {
        case .default: L10n.Localizable.Enum.AppIconType.Value.default
        }
    }

    /// The icon's set in the asset catalog, drawn as its preview in the picker.
    var iconSetName: String { alternateIconName ?? "AppIcon" }
}
