import EhCore
@testable import EhFeatures
import Foundation
import Testing

/// A strip that shows outside a scrub (Shelf's panel): `loadStripThumbnails()`.
@Suite struct ReaderModelStripTests {
    @Test func theStripLoadsItsThumbnailsWhenThePanelAppears() async throws {
        let harness = try ReaderModelHarness()
        let model = await harness.startedModel(initialPage: 10)
        model.previewStripLength = 9
        #expect(harness.site.started.isEmpty)

        model.loadStripThumbnails()

        await readerEventually { model.previewURLs[10] != nil }
        #expect(harness.site.started == ["links:0"])
        #expect(model.previewURLs[6] == harness.site.preview(6))
        #expect(model.previewURLs[14] == harness.site.preview(14))
        // No scrub: the reader stays where it is.
        #expect(!model.showsSliderPreview)
        #expect(harness.engineLog.isEmpty)
    }

    @Test func itFollowsTheReaderOntoTheNextPreviewPageAndAsksForEachOnce() async throws {
        let harness = try ReaderModelHarness()
        let model = await harness.startedModel(initialPage: 30)
        model.previewStripLength = 9
        model.loadStripThumbnails()
        await readerEventually { model.previewURLs[30] != nil }
        model.loadStripThumbnails()
        await readerSettle()
        #expect(harness.site.started == ["links:0"])

        // Turning pages moves the strip onto pages 37 to 45, listed on the second preview page.
        model.currentPageDidChange(41)
        model.loadStripThumbnails()

        await readerEventually { model.previewURLs[45] != nil }
        #expect(harness.site.started == ["links:0", "links:1"])
        model.loadStripThumbnails()
        await readerSettle()
        #expect(harness.site.started == ["links:0", "links:1"])
    }

    @Test func aPreviewPageThatShowsAnotherPageSizeIsFollowedByTheRightOne() async throws {
        // Nothing stored: 40 per preview page is assumed, the site has 20.
        let harness = try ReaderModelHarness(site: ReaderTestSite(batchSize: 20))
        let model = await harness.startedModel(initialPage: 30)
        model.previewStripLength = 9

        model.loadStripThumbnails()
        await readerEventually { !model.previewURLs.isEmpty }
        #expect(model.previewURLs[30] == nil)
        // The design calls again when the preview page arrives.
        model.loadStripThumbnails()

        await readerEventually { model.previewURLs[30] != nil }
        #expect(harness.site.started == ["links:0", "links:1"])
        #expect(model.previewURLs[30] == harness.site.preview(30))
    }

    @Test func duringAScrubItLeavesTheLoadingToWhereTheSliderRests() async throws {
        let harness = try ReaderModelHarness(site: ReaderTestSite(pageCount: 400))
        let model = await harness.startedModel()
        model.previewStripLength = 9
        model.sliderEditingChanged(true)
        await readerEventually { model.previewURLs[1] != nil }

        // Pages 176 to 184 are all listed on the fifth preview page.
        model.setSliderPage(180)
        model.loadStripThumbnails()
        await readerSettle()
        #expect(harness.site.started == ["links:0"])

        await harness.clock.advance(by: ReaderModel.previewDelay)
        await readerEventually { model.previewURLs[180] != nil }
        #expect(harness.site.started == ["links:0", "links:4"])
    }

    @Test func aFailedPreviewPageIsNotAskedForAgain() async throws {
        let harness = try ReaderModelHarness()
        let model = await harness.startedModel()
        model.previewStripLength = 9
        harness.site.fail("links:0")

        model.loadStripThumbnails()
        await readerEventually { harness.site.started == ["links:0"] && harness.site.inFlight.isEmpty }
        await readerSettle()
        model.currentPageDidChange(2)
        model.loadStripThumbnails()
        await readerSettle()

        #expect(harness.site.started == ["links:0"])
    }
}
