import EhModels
import Foundation
import Testing
@testable import EhCore

@Suite struct PageTranslationPolicyTests {
    static let window = TranslationWorld.window(onScreen: [10, 11], ahead: [12, 13, 14, 15], behind: [9])

    static func pages(_ policy: PageTranslationPolicy) -> [Int] {
        policy.pages(of: window).map(\.index)
    }

    @Test func aTranslatorsPagesAhead() {
        #expect(PageTranslationPolicy.pagesAhead(for: .jmtFast1) == 3)
        for languageModel in [TranslatorChoice.galTransl4B, .sakura1_5B, .hyMT2, .qwen35_4B] {
            #expect(PageTranslationPolicy.pagesAhead(for: languageModel) == 1)
        }
    }

    @Test(arguments: [
        // translator, heat, low power, memory pressure → pages ahead, the page before
        (TranslatorChoice.jmtFast1, PageTranslationHeat.nominal, false, false, 3, true),
        (.jmtFast1, .fair, false, false, 3, true),
        (.jmtFast1, .serious, false, false, 0, false),
        (.jmtFast1, .critical, false, false, 0, false),
        (.jmtFast1, .nominal, true, false, 1, false),
        (.jmtFast1, .serious, true, false, 0, false),
        (.jmtFast1, .nominal, false, true, 0, false),
        // A language model: one page ahead, and the page before like every translator.
        (.hyMT2, .nominal, false, false, 1, true),
        (.sakura1_5B, .nominal, false, false, 1, true),
        (.galTransl4B, .fair, false, false, 1, true),
        (.qwen35_4B, .fair, false, false, 1, true),
        (.hyMT2, .fair, true, false, 1, false),
        (.galTransl4B, .serious, false, false, 0, false),
        (.qwen35_4B, .critical, false, false, 0, false),
        (.sakura1_5B, .nominal, false, true, 0, false)
    ])
    func thePolicyOfATranslatorAndThePhonesState(
        translator: TranslatorChoice, heat: PageTranslationHeat, isLowPower: Bool, memoryPressure: Bool,
        ahead: Int, behind: Bool
    ) {
        let policy = PageTranslationPolicy.current(
            translator: translator, heat: heat, isLowPowerModeEnabled: isLowPower, isUnderMemoryPressure: memoryPressure
        )
        #expect(policy == PageTranslationPolicy(pagesAhead: ahead, includesPageBehind: behind))
    }

    @Test func thePagesWorkedOnAreOnScreenThenAheadThenBefore() {
        #expect(Self.pages(PageTranslationPolicy(pagesAhead: 3, includesPageBehind: true)) == [10, 11, 12, 13, 14, 9])
        #expect(Self.pages(PageTranslationPolicy(pagesAhead: 1, includesPageBehind: false)) == [10, 11, 12])
        #expect(Self.pages(.onScreenOnly) == [10, 11])
        // The queue never holds more than the window: two on screen, three ahead, one before.
        #expect(Self.pages(PageTranslationPolicy(pagesAhead: 3, includesPageBehind: true)).count == 6)
    }

    @Test func aPageNamedTwiceIsWorkedOnOnce() {
        let window = TranslationWorld.window(onScreen: [1, 2], ahead: [2, 3], behind: [1])
        #expect(window.pages.map(\.index) == [1, 2, 3])
        #expect(PageTranslationPolicy(pagesAhead: 3, includesPageBehind: true).pages(of: window).map(\.index) == [1, 2, 3])
        #expect(PageTranslationWindow.empty.isEmpty && !window.isEmpty)
    }

    @Test func heatFollowsTheSystemsThermalState() {
        #expect(PageTranslationHeat(.nominal) == .nominal && PageTranslationHeat(.fair) == .fair)
        #expect(PageTranslationHeat(.serious) == .serious && PageTranslationHeat(.critical) == .critical)
        #expect(PageTranslationHeat.fair < .serious && PageTranslationHeat.serious < .critical)
    }

    @Test func statusesThatEndAPagesWork() {
        let overlay = PageTranslationOverlay(patchFile: URL(fileURLWithPath: "/tmp/1.patch"), variant: "v")
        #expect(!PageTranslationStatus.loadingModels.isFinal && !PageTranslationStatus.translating.isFinal)
        for status in [PageTranslationStatus.translated(overlay), .nothingToDraw, .skipped, .failed(.pipelineFailed)] {
            #expect(status.isFinal)
        }
    }
}
