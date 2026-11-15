import EhModels
import Foundation
import Testing

@Suite struct SettingDecodingTests {
    @Test func decodesFullLegacySetting() throws {
        let json = """
        {
          "galleryHost": "ExHentai", "showsNewDawnGreeting": true,
          "enablesTagsExtension": true, "translatesTags": true, "showsTagsSearchSuggestion": true,
          "showsImagesInTags": true, "redirectsLinksToSelectedHost": true,
          "detectsLinksFromClipboard": true, "backgroundBlurRadius": 5, "autoLockPolicy": 60,
          "listDisplayMode": 1, "preferredColorScheme": 2,
          "accentColor": { "red": 0.2, "green": 0.4, "blue": 0.6 },
          "appIconType": 4, "showsTagsInList": true, "listTagsNumberMaximum": 7,
          "displaysJapaneseTitle": false, "readingDirection": 1, "prefetchLimit": 12,
          "enablesLandscape": true, "enablesDualPageMode": true, "exceptCover": true,
          "contentDividerHeight": 4.5, "maximumScaleFactor": 4, "doubleTapScaleFactor": 2.5,
          "bypassesSNIFiltering": true
        }
        """
        let setting = try decodeJSON(Setting.self, json)
        #expect(setting.galleryHost == .exhentai)
        #expect(setting.showsNewDawnGreeting)
        #expect(setting.enablesTagsExtension && setting.translatesTags)
        #expect(setting.showsTagsSearchSuggestion && setting.showsImagesInTags)
        #expect(setting.redirectsLinksToSelectedHost && setting.detectsLinksFromClipboard)
        #expect(setting.backgroundBlurRadius == 5)
        #expect(setting.autoLockPolicy == .min1)
        #expect(setting.listDisplayMode == .thumbnail)
        #expect(setting.preferredColorScheme == .dark)
        #expect(setting.accentColor == RGBColor(red: 0.2, green: 0.4, blue: 0.6))
        #expect(setting.appIconType == .default) // That icon has been removed.
        #expect(setting.showsTagsInList)
        #expect(setting.listTagsNumberMaximum == 7)
        #expect(!setting.displaysJapaneseTitle)
        #expect(setting.readingDirection == .rightToLeft)
        #expect(setting.prefetchLimit == 12)
        #expect(setting.enablesLandscape && setting.enablesDualPageMode && setting.exceptCover)
        #expect(setting.contentDividerHeight == 4.5)
        #expect(setting.maximumScaleFactor == 4)
        #expect(setting.doubleTapScaleFactor == 2.5)
        #expect(setting.bypassesSNIFiltering)
    }

    @Test func missingKeysFallBackToDefaults() throws {
        let setting = try decodeJSON(Setting.self, #"{ "galleryHost": "ExHentai", "prefetchLimit": 20 }"#)
        var expected = Setting()
        expected.galleryHost = .exhentai
        expected.prefetchLimit = 20
        #expect(setting == expected)
        #expect(try decodeJSON(Setting.self, "{}") == Setting())
    }

    @Test func malformedValuesFallBackPerKey() throws {
        let json = """
        { "autoLockPolicy": 42, "accentColor": {}, "prefetchLimit": "many",
          "readingDirection": 2, "listDisplayMode": null }
        """
        let setting = try decodeJSON(Setting.self, json)
        #expect(setting.autoLockPolicy == .never)
        #expect(setting.accentColor == .systemBlue)
        #expect(setting.prefetchLimit == 10)
        #expect(setting.readingDirection == .leftToRight)
        #expect(setting.listDisplayMode == .detail)
    }

    @Test func designFieldsDecodeAndFallBack() throws {
        let json = """
        { "designBar": "command", "designStart": "wall", "designList": "ledger",
          "designGallery": "nope", "designLook": 3, "wallDensity": "small",
          "ledgerShowsCovers": false, "lastFavoriteFolder": 4, "experienceOfferShown": true,
          "lastPlace": "toplists",
          "designCustom": { "bar": "tabs", "start": "ledger", "list": "wall", "gallery": "shelf",
                            "reader": "shelf", "search": "ledger", "library": "wall", "look": "ledger" } }
        """
        let setting = try decodeJSON(Setting.self, json)
        #expect(setting.designBar == .command)
        #expect(setting.designStart == .wall)
        #expect(setting.designList == .ledger)
        #expect(setting.designGallery == .shelf)
        #expect(setting.designLook == .shelf)
        #expect(setting.designCustom?.start == .ledger)
        #expect(setting.wallDensity == .small)
        #expect(!setting.ledgerShowsCovers)
        #expect(setting.lastFavoriteFolder == 4)
        #expect(setting.lastPlace == .toplists)
        #expect(setting.experienceOfferShown)
        #expect(try decodeJSON(Setting.self, #"{ "designCustom": { "bar": "tabs" } }"#).designCustom == nil)
        #expect(try decodeJSON(Setting.self, #"{ "lastPlace": "index" }"#).lastPlace == nil)
        #expect(try decodeJSON(Setting.self, #"{ "lastPlace": null }"#).lastPlace == nil)
    }

    @Test func designDefaultsAreTheShelfPreset() {
        let setting = Setting()
        let choices = DesignChoices(
            bar: setting.designBar, start: setting.designStart, list: setting.designList,
            gallery: setting.designGallery, reader: setting.designReader, search: setting.designSearch,
            library: setting.designLibrary, look: setting.designLook
        )
        #expect(choices == DesignChoices(preset: .shelf))
        #expect(setting.designCustom == nil)
        #expect(setting.wallDensity == .medium)
        #expect(setting.ledgerShowsCovers)
        #expect(setting.lastFavoriteFolder == 0)
        #expect(setting.lastPlace == nil)
        #expect(!setting.experienceOfferShown)
    }

    @Test func nonObjectDecodesAsDefaults() throws {
        #expect(try decodeJSON(Setting.self, "[]") == Setting())
    }

    @Test func roundTrips() throws {
        var setting = Setting()
        setting.galleryHost = .exhentai
        setting.enablesTagsExtension = true
        setting.translatesTags = true
        setting.accentColor = RGBColor(red: 1, green: 0.5, blue: 0)
        setting.autoLockPolicy = .min30
        setting.designList = .ledger
        setting.designCustom = DesignChoices(preset: .wall)
        setting.wallDensity = .large
        setting.lastPlace = .favorites
        #expect(try roundTrip(setting) == setting)
    }

    @Test func disablingTagsExtensionClearsDependentOptions() {
        var setting = Setting()
        setting.enablesTagsExtension = true
        setting.translatesTags = true
        setting.showsTagsSearchSuggestion = true
        setting.showsImagesInTags = true
        setting.enablesTagsExtension = false
        #expect(!setting.translatesTags && !setting.showsTagsSearchSuggestion && !setting.showsImagesInTags)
    }

    @Test func defaults() {
        let setting = Setting()
        #expect(setting.galleryHost == .ehentai)
        #expect(setting.listDisplayMode == .detail)
        #expect(setting.accentColor == .systemBlue)
        #expect(setting.backgroundBlurRadius == 10)
        #expect(setting.prefetchLimit == 10)
        #expect(setting.maximumScaleFactor == 3 && setting.doubleTapScaleFactor == 2)
        #expect(setting.displaysJapaneseTitle)
    }
}
