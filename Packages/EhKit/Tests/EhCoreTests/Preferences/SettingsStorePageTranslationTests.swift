@testable import EhCore
import EhModels
import Foundation
import Testing

@MainActor @Suite struct SettingsStorePageTranslationTests {
    @Test func defaultsWriteNothing() {
        let storage = PreferenceStorage.ephemeral()
        let store = SettingsStore(storage: storage)
        #expect(store.pageTranslationModelSet == .default)
        #expect(store.pageTranslationRepaint == .lamaManga)
        #expect(store.pageTranslationSourceAddress.isEmpty)
        #expect(storage.storedSettingKeys.isEmpty)
    }

    @Test func storedRepresentations() {
        let storage = PreferenceStorage.ephemeral()
        let store = SettingsStore(storage: storage)
        store.pageTranslationDetector = .yolo26s
        store.pageTranslationReader = .narSmall
        store.pageTranslationTranslator = .qwen35_4B
        store.pageTranslationRepaint = .off
        store.pageTranslationSourceAddress = "https://models.example"
        let defaults = storage.defaults
        #expect(defaults.string(forKey: "settings.pageTranslationDetector") == "yolo26s")
        #expect(defaults.string(forKey: "settings.pageTranslationReader") == "narSmall")
        #expect(defaults.string(forKey: "settings.pageTranslationTranslator") == "qwen35_4B")
        #expect(defaults.string(forKey: "settings.pageTranslationRepaint") == "off")
        #expect(defaults.string(forKey: "settings.pageTranslationSourceAddress") == "https://models.example")
        let reloaded = SettingsStore(storage: storage)
        #expect(reloaded.pageTranslationModelSet == PageTranslationModelSet(
            detector: .yolo26s, reader: .narSmall, translator: .qwen35_4B
        ))
        #expect(reloaded.pageTranslationRepaint == .off)
    }

    @Test func unknownStoredChoicesFallBackToDefaults() {
        let storage = PreferenceStorage.ephemeral()
        storage.defaults.set("someFutureDetector", forKey: "settings.pageTranslationDetector")
        storage.defaults.set("mangaOCRARExperimental", forKey: "settings.pageTranslationReader")
        storage.defaults.set("translateGemma4B", forKey: "settings.pageTranslationTranslator")
        storage.defaults.set(true, forKey: "settings.pageTranslationRepaint")
        storage.defaults.set(42, forKey: "settings.pageTranslationSourceAddress")
        let store = SettingsStore(storage: storage)
        #expect(store.pageTranslationModelSet == .default)
        #expect(store.pageTranslationRepaint == .lamaManga)
        #expect(store.pageTranslationSourceAddress.isEmpty)
    }

    @Test func modelSetObservesOnlyTheModelSettings() {
        let store = SettingsStore(storage: .ephemeral())
        let read = { _ = store.pageTranslationModelSet }
        #expect(changeIsObserved(reading: read, after: { store.pageTranslationDetector = .rtmdet2 }))
        #expect(changeIsObserved(reading: read, after: { store.pageTranslationReader = .narSmall }))
        #expect(changeIsObserved(reading: read, after: { store.pageTranslationTranslator = .hyMT2 }))
        #expect(!changeIsObserved(reading: read, after: { store.pageTranslationRepaint = .bigLama }))
        #expect(!changeIsObserved(reading: read, after: { store.pageTranslationSourceAddress = "x" }))
    }
}
