@testable import EhFeatures
import Foundation
import Testing

/// A scrub that ends without choosing a page: `cancelSliderEditing()`.
@Suite struct ReaderModelScrubTests {
    @Test func aCancelledScrubLeavesTheReaderAndReturnsTheSlider() async throws {
        let harness = try ReaderModelHarness()
        let model = await harness.startedModel(initialPage: 10)
        model.setAutoPlay(.threeSeconds)
        model.sliderEditingChanged(true)
        model.setSliderPage(30)
        #expect(model.sliderPage == 30)

        model.cancelSliderEditing()

        #expect(!model.showsSliderPreview)
        #expect(model.sliderPage == 10)
        #expect(harness.engineLog.isEmpty)
        // Starting the scrub turned auto-play off, as any scrub does; cancelling keeps it off.
        #expect(model.autoPlay == .off)
        // The slider follows the reader again.
        model.currentPageDidChange(11)
        #expect(model.sliderPage == 11)
    }

    @Test func itFetchesNothingForWhereTheSliderWas() async throws {
        let harness = try ReaderModelHarness(site: ReaderTestSite(pageCount: 400))
        let model = await harness.startedModel()
        model.sliderEditingChanged(true)
        await readerEventually { model.previewURLs[1] != nil }
        model.setSliderPage(180)

        model.cancelSliderEditing()
        await harness.clock.advance(by: ReaderModel.previewDelay)
        await readerSettle()

        #expect(harness.site.started == ["links:0"])
    }

    /// Letting go on the closing page goes back to the last page; a cancelled scrub stays.
    @Test func onTheClosingPageACancelledScrubStaysThere() async throws {
        let harness = try ReaderModelHarness()
        let model = await harness.startedModel(initialPage: 100)
        model.trailerVisibilityDidChange(true)

        model.sliderEditingChanged(true)
        model.cancelSliderEditing()

        #expect(model.isAtEnd)
        #expect(model.sliderPage == 100)
        #expect(harness.engineLog.isEmpty)

        model.sliderEditingChanged(true)
        model.sliderEditingChanged(false)
        #expect(harness.engineLog == ["scroll:100"])
    }

    @Test func withoutAScrubItDoesNothing() async throws {
        let harness = try ReaderModelHarness()
        let model = await harness.startedModel(initialPage: 10)

        model.cancelSliderEditing()

        #expect(!model.showsSliderPreview)
        #expect(model.sliderPage == 10)
        #expect(harness.engineLog.isEmpty)
    }
}
