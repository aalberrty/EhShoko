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

    @Test(arguments: ["AppIcon_Default", "AppIcon_Ukiyoe", ""])
    func anAlternateNameNoIconHasIsThePrimaryIcon(name: String) {
        #expect(AppIconType(alternateIconName: name) == .default)
    }

    /// A value stored while one of the removed icons was chosen must not select a new icon.
    @Test func removedIconsKeepTheirRawValues() {
        #expect(AppIconType.allCases.allSatisfy { !(1...4).contains($0.rawValue) })
    }

    @Test(arguments: 1...4)
    func aRemovedIconDecodesAsTheDefault(rawValue: Int) throws {
        #expect(AppIconType(rawValue: rawValue) == nil)
        let setting = try decodeJSON(Setting.self, #"{ "appIconType": \#(rawValue), "prefetchLimit": 20 }"#)
        #expect(setting.appIconType == .default)
        #expect(setting.prefetchLimit == 20)
    }
}
