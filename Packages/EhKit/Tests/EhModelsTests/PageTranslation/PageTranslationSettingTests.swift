import EhModels
import Foundation
import Testing

@Suite struct PageTranslationSettingTests {
    @Test func defaultsAreTheDefaultModelsWithRepaintOn() {
        let setting = Setting()
        #expect(setting.pageTranslationDetector == .k2xl)
        #expect(setting.pageTranslationReader == .cpt2)
        #expect(setting.pageTranslationTranslator == .jmtFast1)
        #expect(setting.pageTranslationRepaint == .lamaManga)
        #expect(!setting.pageTranslationTranslatesSoundEffects)
        #expect(setting.pageTranslationSourceAddress.isEmpty)
        #expect(setting.pageTranslationModelSet == .default)
    }

    @Test func theModelSetCarriesTheSwitchForSoundEffects() {
        var setting = Setting()
        setting.pageTranslationTranslatesSoundEffects = true
        #expect(setting.pageTranslationModelSet == PageTranslationModelSet(translatesSoundEffects: true))
        #expect(setting.pageTranslationModelSet.key != PageTranslationModelSet.default.key)
    }

    @Test func theModelSetFollowsTheThreeChoices() {
        var setting = Setting()
        setting.pageTranslationDetector = .yolo26s
        setting.pageTranslationReader = .narSmall
        setting.pageTranslationTranslator = .galTransl4B
        #expect(setting.pageTranslationModelSet == PageTranslationModelSet(
            detector: .yolo26s, reader: .narSmall, translator: .galTransl4B
        ))
    }
}
