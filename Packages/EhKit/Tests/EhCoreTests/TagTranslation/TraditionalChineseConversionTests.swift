import EhModels
import Foundation
import Testing
@testable import EhCore

@Suite struct TraditionalChineseConversionTests {
    static let source = Samples.keyed([
        Samples.translation(.female, "a", "头发里面为线", description: "头发"),
        Samples.translation(.other, "full color", "full color"),
        Samples.translation(.other, "memory", "内存")
    ])

    private func values(_ languages: [String]) -> [String: String] {
        TagTranslationPreparation.traditionalChineseConverted(Self.source, preferredLanguages: languages)
            .mapValues(\.value)
    }

    @Test func hongKongStandard() {
        let values = values(["zh-Hant-HK"])
        // 為 differs from plain traditionalisation (爲), 裏 from Taiwan (裡).
        #expect(values["femalea"] == "頭髮裏面為線")
        #expect(values["othermemory"] == "內存")
    }

    @Test func taiwanStandardWithIdioms() {
        let values = values(["zh-Hant-TW"])
        #expect(values["femalea"] == "頭髮裡面為線")
        #expect(values["othermemory"] == "記憶體")
    }

    @Test func otherLocalesUsePlainTraditionalisation() {
        let values = values(["zh-Hant"])
        #expect(values["femalea"] == "頭髮裏面爲線")
        #expect(values["othermemory"] == "內存")
    }

    @Test func fullColorFixUpAndUntouchedFields() {
        let converted = TagTranslationPreparation.traditionalChineseConverted(
            Self.source, preferredLanguages: ["zh-Hant"]
        )
        #expect(converted["otherfull color"]?.value == "全彩")
        #expect(converted["femalea"]?.description == "头发")
    }

    @Test func noPreferredLanguageLeavesValuesUnchanged() {
        let unchanged = TagTranslationPreparation.traditionalChineseConverted(Self.source, preferredLanguages: [])
        #expect(unchanged == Self.source)
    }
}
