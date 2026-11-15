import Foundation

/// The app icons a user can pick. Raw values are persisted, and one that no case has (an icon
/// since removed) reads as `.default`.
public enum AppIconType: Int, Codable, Sendable, Hashable, CaseIterable, Identifiable {
    /// The primary icon, `AppIcon` in the asset catalog.
    case `default`
    // Raw values 1 to 4 were icons that have been removed. A new icon takes 5 or later, so a
    // value stored for one of them never selects it.

    public var id: Int { rawValue }

    /// The name `UIApplication.setAlternateIconName(_:)` takes and `alternateIconName`
    /// reports, which is also the icon's set in the asset catalog; `nil` for the primary icon.
    public var alternateIconName: String? {
        switch self {
        case .default: nil
        }
    }

    /// The icon the system shows, given its alternate icon name: `nil` is the primary icon,
    /// and so is a name no case has (an icon since removed).
    public init(alternateIconName name: String?) {
        self = Self.allCases.first { $0.alternateIconName == name } ?? .default
    }
}
