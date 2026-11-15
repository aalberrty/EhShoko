import EhModels
import Testing

@Suite struct SettingTests {
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
