@testable import EhFeatures
import EhModels
import Foundation
import Testing

/// The closing page after the last page, as the model sees it: `isAtEnd` and auto-play.
@Suite struct ReaderModelClosingPageTests {
    @Test func notAtTheEndUntilTheEngineReportsTheClosingPage() async throws {
        let harness = try ReaderModelHarness()
        let model = await harness.startedModel(initialPage: 100)
        #expect(!model.isAtEnd)
        #expect(model.translationAvailability == .ready)

        model.trailerVisibilityDidChange(true)
        #expect(model.isAtEnd)
        // It is not a page: the current page stays the last one.
        #expect(model.currentPage == 100)
        #expect(model.sliderPage == 100)

        model.trailerVisibilityDidChange(false)
        #expect(!model.isAtEnd)
    }

    /// With a closing page, auto-play advances past the last page onto it and stops there.
    @Test func autoPlayMakesItsLastAdvanceOntoTheClosingPage() async throws {
        let harness = try ReaderModelHarness()
        let model = await harness.startedModel(initialPage: 99)
        model.hasTrailer = true
        model.setAutoPlay(.oneSecond)
        await harness.clock.advance(by: .seconds(1))
        model.currentPageDidChange(100)
        #expect(model.autoPlay == .oneSecond)

        await harness.clock.advance(by: .seconds(1))
        #expect(harness.engineCount("advance") == 2)
        model.trailerVisibilityDidChange(true)

        #expect(model.autoPlay == .off)
        await harness.clock.advance(by: .seconds(5))
        #expect(harness.engineCount("advance") == 2)
    }

    /// Without one (today's engine), auto-play still stops on the last page.
    @Test func withoutAClosingPageAutoPlayStopsOnTheLastPage() async throws {
        let harness = try ReaderModelHarness()
        let model = await harness.startedModel(initialPage: 99)
        model.setAutoPlay(.oneSecond)
        model.currentPageDidChange(100)
        #expect(model.autoPlay == .off)
        #expect(!model.isAtEnd)
    }

    /// The last page is somewhere to go back to from the closing page.
    @Test func theSliderLeavesTheClosingPageForTheLastPage() async throws {
        let harness = try ReaderModelHarness()
        let model = await harness.startedModel(initialPage: 100)
        model.trailerVisibilityDidChange(true)
        model.previewStripLength = 9
        #expect(model.previewStripPages == Array(96...104))

        model.sliderEditingChanged(true)
        model.sliderEditingChanged(false)
        #expect(harness.engineLog.contains("scroll:100"))
    }
}

/// From `ui-overhaul` `fa1993de`: the reader shows the gallery page's title.
@Suite struct ReaderModelTitleTests {
    @Test func theTitleIsTheStoredDetailsOnceStarted() async throws {
        let harness = try ReaderModelHarness()
        try await harness.storeDetail(previewConfig: .large(rows: 4), jpnTitle: "タイトル")
        var gallery = harness.site.gallery
        gallery.title = "List title"
        let model = harness.makeModel(gallery: gallery)
        #expect(model.title(prefersJapanese: true) == "List title")

        await model.start()

        #expect(model.title(prefersJapanese: true) == "タイトル")
        #expect(model.title(prefersJapanese: false) == "Title")
    }

    @Test func theOpenersDetailIsUsedOverTheStoredOne() async throws {
        let harness = try ReaderModelHarness()
        try await harness.storeDetail(previewConfig: .large(rows: 4), jpnTitle: "Stored")
        var detail = GalleryDetail.preview
        detail.jpnTitle = "Fresh"
        let model = harness.makeModel(detail: detail)
        #expect(model.title(prefersJapanese: true) == "Fresh")

        await model.start()

        #expect(model.title(prefersJapanese: true) == "Fresh")
        #expect(model.title(prefersJapanese: false) == "Preview")
    }

    @Test func withoutADetailTheTitleIsTheListsTitle() async throws {
        let harness = try ReaderModelHarness()
        let model = await harness.startedModel()
        #expect(model.title(prefersJapanese: true) == "Title")
        #expect(model.title(prefersJapanese: false) == "Title")
    }
}
