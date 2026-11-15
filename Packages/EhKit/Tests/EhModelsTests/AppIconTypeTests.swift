import EhModels
import Testing

@Suite struct AppIconTypeTests {
    @Test func theDefaultIsThePrimaryIcon() {
        #expect(AppIconType.default.alternateIconName == nil)
        #expect(AppIconType(alternateIconName: nil) == .default)
    }

    @Test func everyIconIsFoundByItsAlternateName() {
        for icon in AppIconType.allCases {
            #expect(AppIconType(alternateIconName: icon.alternateIconName) == icon)
        }
    }

    @Test(arguments: ["AppIcon_Removed", "Unknown", ""])
    func anAlternateNameNoIconHasIsThePrimaryIcon(name: String) {
        #expect(AppIconType(alternateIconName: name) == .default)
    }

    /// A value stored while one of the removed icons was chosen must not select a new icon.
    @Test func removedIconsKeepTheirRawValues() {
        #expect(AppIconType.allCases.allSatisfy { !(1...4).contains($0.rawValue) })
    }

    /// A removed icon's raw value has no case; `SettingsStore` reads such a stored value as the
    /// default (`SettingsStoreTests`).
    @Test(arguments: 1...4)
    func aRemovedIconHasNoCase(rawValue: Int) {
        #expect(AppIconType(rawValue: rawValue) == nil)
    }
}
