@testable import EhCore
import EhModels
import Foundation
import Testing

@MainActor @Suite struct SettingsStoreDesignTests {
    private static let designKeys: [SettingKey] = [
        .designBar, .designStart, .designList, .designGallery,
        .designReader, .designSearch, .designLibrary, .designLook
    ]

    @Test func defaultsAreTheShelfPreset() {
        let store = SettingsStore(storage: .ephemeral())
        #expect(store.designChoices == DesignChoices(preset: .shelf))
        #expect(store.designPreset == .shelf)
        #expect(store.designCustom == nil)
        #expect(store.look == .shelf)
        #expect(!store.experienceOfferShown)
    }

    @Test(arguments: DesignStyle.allCases)
    func eachPresetRoundTrips(style: DesignStyle) {
        let storage = PreferenceStorage.ephemeral()
        let store = SettingsStore(storage: storage)
        store.applyDesignPreset(style)
        #expect(store.designPreset == style)
        #expect(store.designChoices == DesignChoices(preset: style))
        #expect(store.designCustom == nil)
        #expect(SettingsStore(storage: storage).designPreset == style)
    }

    @Test func changingOnePartMakesACustomMix() {
        let storage = PreferenceStorage.ephemeral()
        let store = SettingsStore(storage: storage)
        store.applyDesignPreset(.wall)
        store.setDesign(.style(.ledger), for: .list)
        #expect(store.designPreset == nil)
        #expect(store.designList == .ledger)
        var expected = DesignChoices(preset: .wall)
        expected.list = .ledger
        #expect(store.designCustom == expected)
        #expect(SettingsStore(storage: storage).designCustom == expected)
    }

    @Test func settingAPresetThroughOnePartLeavesCustomAlone() {
        let store = SettingsStore(storage: .ephemeral())
        store.setDesign(.bar(.command), for: .bar)
        let mix = store.designChoices
        store.setDesign(.bar(.tabs), for: .bar)
        #expect(store.designPreset == .shelf)
        #expect(store.designCustom == mix)
    }

    @Test func restoreCustomDesignBringsTheMixBack() {
        let store = SettingsStore(storage: .ephemeral())
        store.setDesign(.style(.wall), for: .reader)
        let mix = store.designChoices
        store.applyDesignPreset(.ledger)
        #expect(store.designCustom == mix)
        store.restoreCustomDesign()
        #expect(store.designChoices == mix)
    }

    @Test func restoreWithoutAMixChangesNothing() {
        let storage = PreferenceStorage.ephemeral()
        let store = SettingsStore(storage: storage)
        store.restoreCustomDesign()
        #expect(store.designPreset == .shelf)
        #expect(storage.storedSettingKeys.isEmpty)
    }

    @Test func assigningChoicesWritesOnlyTheChangedParts() {
        let storage = PreferenceStorage.ephemeral()
        let store = SettingsStore(storage: storage)
        var choices = DesignChoices(preset: .shelf)
        choices.look = .ledger
        choices.search = .wall
        store.designChoices = choices
        #expect(storage.storedSettingKeys == [.designLook, .designSearch, .designCustom])
        #expect(!changeIsObserved(reading: { _ = store.designList }, after: { store.designChoices = choices }))
    }

    @Test func applyingAPresetNotifiesOnlyChangedParts() {
        let store = SettingsStore(storage: .ephemeral())
        store.setDesign(.style(.wall), for: .look)
        #expect(!changeIsObserved(reading: { _ = store.designList }, after: { store.applyDesignPreset(.shelf) }))
        #expect(changeIsObserved(reading: { _ = store.designLook }, after: { store.applyDesignPreset(.ledger) }))
    }

    @Test func theLookFollowsDesignLook() {
        let store = SettingsStore(storage: .ephemeral())
        for style in DesignStyle.allCases {
            store.setDesign(.style(style), for: .look)
            #expect(store.look == style)
        }
        store.setDesign(.style(.ledger), for: .start)
        #expect(store.look == .ledger)
        store.setDesign(.style(.wall), for: .start)
        #expect(store.look == .ledger)
    }

    @Test func keysAndRawValues() {
        let storage = PreferenceStorage.ephemeral()
        SettingsStore(storage: storage).apply(.nonDefault)
        let defaults = storage.defaults
        #expect(defaults.string(forKey: "settings.designBar") == "command")
        #expect(defaults.string(forKey: "settings.designLook") == "wall")
        #expect(defaults.string(forKey: "settings.wallDensity") == "small")
        #expect(defaults.object(forKey: "settings.lastFavoriteFolder") as? Int == 7)
        #expect(defaults.object(forKey: "settings.experienceOfferShown") as? Bool == true)
        let custom = defaults.dictionary(forKey: "settings.designCustom") as? [String: String]
        #expect(custom?["bar"] == "tabs")
        #expect(custom?["look"] == "ledger")
        #expect(custom?.count == 8)
    }

    @Test func clearingCustomRemovesItsKey() {
        let storage = PreferenceStorage.ephemeral()
        let store = SettingsStore(storage: storage)
        store.setDesign(.style(.wall), for: .gallery)
        #expect(storage.contains(.designCustom))
        store.designCustom = nil
        #expect(!storage.contains(.designCustom))
    }

    @Test func unknownRawValuesFallBack() {
        let storage = PreferenceStorage.ephemeral()
        for key in Self.designKeys {
            storage.defaults.set("gallery", forKey: key.name)
        }
        storage.defaults.set("huge", forKey: "settings.wallDensity")
        storage.defaults.set(["bar": "tabs", "start": "wall"], forKey: "settings.designCustom")
        storage.defaults.set(12, forKey: "settings.lastFavoriteFolder")
        let store = SettingsStore(storage: storage)
        #expect(store.designChoices == DesignChoices(preset: .shelf))
        #expect(store.wallDensity == .medium)
        #expect(store.designCustom == nil)
        #expect(store.lastFavoriteFolder == 9)
    }

    @Test func theFavouriteFolderStaysInRange() {
        let store = SettingsStore(storage: .ephemeral())
        store.lastFavoriteFolder = 15
        #expect(store.lastFavoriteFolder == 9)
        store.lastFavoriteFolder = -2
        #expect(store.lastFavoriteFolder == 0)
        store.lastFavoriteFolder = 3
        #expect(store.lastFavoriteFolder == 3)
    }

    @Test func theLegacyImportLeavesTheDesignAtItsDefaults() async {
        let storage = PreferenceStorage.ephemeral()
        let settings = SettingsStore(storage: storage)
        let blobs = LegacyPreferenceBlobs(
            setting: json(#"{ "listDisplayMode": 1, "prefetchLimit": 18, "readingDirection": 1 }"#),
            user: nil, searchFilter: nil, globalFilter: nil, watchedFilter: nil
        )
        _ = await blobs.apply(to: settings, filters: FilterStore(storage: storage), user: UserStore(storage: storage))
        #expect(settings.prefetchLimit == 18)
        #expect(settings.designChoices == DesignChoices(preset: .shelf))
        #expect(settings.designCustom == nil)
        #expect(!settings.experienceOfferShown)
        #expect(settings.wallDensity == .medium && settings.ledgerShowsCovers && settings.lastFavoriteFolder == 0)
        let stored = storage.storedSettingKeys
        #expect(stored.isDisjoint(with: Self.designKeys + [.designCustom, .experienceOfferShown]))
    }
}
