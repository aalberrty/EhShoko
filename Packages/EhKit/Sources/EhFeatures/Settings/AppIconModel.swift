import Dependencies
import EhCore
import EhModels
import Observation

/// The app icon picker. The selected icon is `SettingsStore.appIconType`, kept in step with
/// the icon the system actually shows.
@Observable
public final class AppIconModel {
    @ObservationIgnored @Dependency(\.settings) private var settings
    @ObservationIgnored @Dependency(\.applicationClient) private var application

    /// Whether Settings offers the icon picker. With one icon there is nothing to choose, so
    /// the row that opens it is hidden.
    public static var offersChoice: Bool { AppIconType.allCases.count > 1 }

    public init() {}

    /// Asks the system to switch icons (it shows its own alert), then records what it reports,
    /// so a refused change does not leave the wrong icon checked. The icon already shown is not
    /// asked for again, which would only bring up the alert.
    public func select(_ icon: AppIconType) async {
        settings.appIconType = icon
        if application.alternateIconName() != icon.alternateIconName {
            _ = await application.setAlternateIconName(icon.alternateIconName)
        }
        syncWithSystem()
    }

    /// Sets `appIconType` to the icon the system reports; the primary icon is `.default`.
    public func syncWithSystem() {
        settings.appIconType = AppIconType(alternateIconName: application.alternateIconName())
    }
}
