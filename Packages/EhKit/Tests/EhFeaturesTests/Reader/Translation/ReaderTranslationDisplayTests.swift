import EhCore
import EhDatabase
@testable import EhFeatures
import EhModels
import Foundation
import Testing

/// While Translate is on: the window following the page, the current page's status, the
/// overlays and the commands sent to the engine, the display and Retry.
@Suite struct ReaderTranslationDisplayTests {
    /// A reader at `page` with Translate on and the window sent.
    private func translatingModel(
        _ harness: ReaderTranslationHarness, page: Int = 5, storesImageURLs: Bool = true
    ) async throws -> ReaderModel {
        try await harness.models.installDefaultSet()
        if storesImageURLs { try await harness.storeImageURLs() }
        let model = await harness.openedModel(initialPage: page)
        model.toggleTranslation()
        await readerEventually { model.translation.isOn }
        harness.clearLog()
        return model
    }

    @Test func theWindowFollowsTheCurrentPage() async throws {
        let harness = try ReaderTranslationHarness()
        let model = try await translatingModel(harness)

        model.currentPageDidChange(9)
        let window = try #require(harness.service.lastWindow)
        #expect(window.onScreen.map(\.index) == [9])
        #expect(window.ahead.map(\.index) == [10])
        #expect(window.behind.map(\.index) == [8])

        // The same page again sends nothing.
        let count = harness.service.windows.count
        model.currentPageDidChange(9)
        #expect(harness.service.windows.count == count)
    }

    @Test func theOtherPageOfASpreadIsOnScreen() async throws {
        let harness = try ReaderTranslationHarness()
        let model = try await translatingModel(harness, page: 4)
        #expect(harness.service.lastWindow?.onScreen.map(\.index) == [4])

        // The engine shows pages 4 and 5 side by side.
        model.pagesOnScreenDidChange([4, 5])
        var window = try #require(harness.service.lastWindow)
        #expect(window.onScreen.map(\.index) == [4, 5])
        #expect(window.ahead.map(\.index) == [6, 7, 8])
        #expect(window.behind.map(\.index) == [3])

        // A turn of the spread, as the engine reports it: the pages first, then the current
        // page. One new window, with both pages on screen.
        let count = harness.service.windows.count
        model.pagesOnScreenDidChange([6, 7])
        #expect(harness.service.windows.count == count)
        model.currentPageDidChange(6)
        #expect(harness.service.windows.count == count + 1)
        window = try #require(harness.service.lastWindow)
        #expect(window.onScreen.map(\.index) == [6, 7])
        #expect(window.ahead.map(\.index) == [8, 9, 10])
        #expect(window.behind.map(\.index) == [5])

        // The same pages again send nothing.
        model.pagesOnScreenDidChange([6, 7])
        #expect(harness.service.windows.count == count + 1)
    }

    @Test func thePagesOnScreenAreKeptFromBeforeThePress() async throws {
        let harness = try ReaderTranslationHarness()
        try await harness.models.installDefaultSet()
        try await harness.storeImageURLs()
        let model = await harness.openedModel(initialPage: 2)
        // Off: the engine says what it shows, and nothing is asked of anyone.
        model.pagesOnScreenDidChange([2, 3])
        await readerSettle()
        #expect(harness.service.opened.isEmpty)
        #expect(harness.service.windows.isEmpty)
        #expect(harness.log.isEmpty)

        model.toggleTranslation()
        await readerEventually { model.translation.isOn }
        #expect(harness.service.lastWindow?.onScreen.map(\.index) == [2, 3])
        #expect(harness.service.lastWindow?.ahead.map(\.index) == [4, 5, 6])
    }

    @Test func aPageIsSentOnceItsImageAddressIsKnown() async throws {
        let harness = try ReaderTranslationHarness()
        try await harness.database.upsertPages([
            GalleryPage(gid: harness.gid, index: 1, pageURL: harness.reader.site.link(1), imageURL: harness.image(1))
        ])
        let model = try await translatingModel(harness, page: 1, storesImageURLs: false)
        #expect(harness.service.lastWindow?.pages.map(\.index) == [1])

        model.pagesNeeded([2])
        await readerEventually { harness.service.lastWindow?.ahead.map(\.index) == [2] }
        #expect(harness.service.lastWindow?.ahead == [PageTranslationPage(index: 2, imageURL: harness.image(2))])
    }

    @Test func onlyTheCurrentPagesStatusIsShown() async throws {
        let harness = try ReaderTranslationHarness()
        let model = try await translatingModel(harness)
        #expect(model.translation.status == nil)

        harness.service.yield(5, .loadingModels)
        await readerEventually { model.translation.status == .gettingReady }
        harness.service.yield(5, .translating)
        await readerEventually { model.translation.status == .translating(page: 5) }
        harness.service.yield(6, .failed(.pipelineFailed))
        harness.service.yield(5, .nothingToDraw)
        await readerEventually { model.translation.status == .nothingToDraw }

        model.currentPageDidChange(6)
        #expect(model.translation.status == .failed(page: 6))
        // An animated page shows nothing.
        harness.service.yield(6, .skipped)
        await readerEventually { model.translation.status == nil }
    }

    @Test func translatedPagesKeepTheirOverlayAfterLeavingTheWindow() async throws {
        let harness = try ReaderTranslationHarness()
        let model = try await translatingModel(harness)
        harness.service.yield(5, .translated(ReaderTranslationHarness.overlay(5)))
        await readerEventually { model.translationOverlay(at: 5) != nil }

        model.currentPageDidChange(10)
        #expect(model.translationOverlay(at: 5) == ReaderTranslationHarness.overlay(5))
        // The same overlay again is no change for the engine; a new one is.
        harness.service.yield(5, .translated(ReaderTranslationHarness.overlay(5)))
        harness.service.yield(5, .translated(ReaderTranslationHarness.overlay(5, "v2")))
        await readerEventually { model.translationOverlay(at: 5)?.variant == "v2" }
        #expect(harness.log == ["translation:5", "translation:5"])
    }

    @Test func pressingAgainTurnsItOffAndKeepsTheSession() async throws {
        let harness = try ReaderTranslationHarness()
        let model = try await translatingModel(harness)
        harness.service.yield(5, .translated(ReaderTranslationHarness.overlay(5)))
        await readerEventually { model.translation.status == .translated }

        model.toggleTranslation()
        #expect(!model.translation.isOn)
        #expect(harness.service.lastWindow == .empty)
        #expect(model.translation.status == nil)
        #expect(model.translationDisplay == .original)
        // Off gives the engine no overlay: page 5 is asked about again and lets its go.
        #expect(harness.log == ["translation:5", "display:original", "translation:5"])
        model.currentPageDidChange(6)
        #expect(harness.service.lastWindow == .empty)

        model.toggleTranslation()
        await readerEventually { model.translation.isOn }
        #expect(harness.service.opened.count == 1)
        #expect(harness.service.lastWindow?.onScreen.map(\.index) == [6])
        #expect(Array(harness.log.suffix(2)) == ["display:translated", "translation:5"])
        #expect(harness.service.closes == 0)
    }

    @Test func holdingShowsTheOriginalWhileHeld() async throws {
        let harness = try ReaderTranslationHarness()
        let model = try await translatingModel(harness)

        model.translation.holdOriginal(true)
        #expect(model.translationDisplay == .original)
        model.translation.holdOriginal(false)
        #expect(model.translationDisplay == .translated)
        #expect(harness.log == ["display:original", "display:translated"])
        // Translate stays on and the work goes on.
        #expect(model.translation.isOn)
        #expect(harness.service.lastWindow != .empty)
    }

    @Test func theDisplayModeIsSentToTheEngine() async throws {
        let harness = try ReaderTranslationHarness()
        let model = try await translatingModel(harness)

        model.translation.setDisplayMode(.original)
        model.translation.setDisplayMode(.compare)
        model.translation.setCompareFraction(0.25)
        model.translation.setCompareFraction(4)
        model.translation.setDisplayMode(.translated)

        #expect(harness.log == [
            "display:original", "display:compare(fraction: 0.5)", "display:compare(fraction: 0.25)",
            "display:compare(fraction: 1.0)", "display:translated"
        ])
        #expect(harness.service.lastWindow != .empty)
    }

    @Test func theWipeComesBackWhereItWasLeft() async throws {
        let harness = try ReaderTranslationHarness()
        let model = try await translatingModel(harness)
        #expect(model.translation.compareFraction == 0.5)

        model.translation.setDisplayMode(.compare)
        model.translation.setCompareFraction(0.3)
        model.translation.setCompareFraction(-1)
        #expect(model.translation.compareFraction == 0)
        model.translation.setCompareFraction(0.3)
        model.translation.setDisplayMode(.translated)
        model.translation.setDisplayMode(.compare)

        #expect(model.translation.compareFraction == 0.3)
        #expect(harness.log.suffix(2) == ["display:translated", "display:compare(fraction: 0.3)"])
    }

    @Test func retryAsksForTheFailedPageAgain() async throws {
        let harness = try ReaderTranslationHarness()
        let model = try await translatingModel(harness)
        model.retryTranslation()
        #expect(harness.service.retries.isEmpty)

        harness.service.yield(5, .failed(.pipelineFailed))
        await readerEventually { model.translation.status == .failed(page: 5) }
        model.retryTranslation()
        #expect(harness.service.retries == [5])
    }

    @Test func anOverlayTheEngineCannotReadIsDrawnAgain() async throws {
        let harness = try ReaderTranslationHarness()
        let model = try await translatingModel(harness)
        harness.service.yield(5, .translated(ReaderTranslationHarness.overlay(5)))
        await readerEventually { model.translationOverlay(at: 5) != nil }

        model.translationOverlayDidFail(page: 5)
        #expect(model.translationOverlay(at: 5) == nil)
        #expect(harness.service.retries == [5])
        #expect(harness.log == ["translation:5", "translation:5"])
    }
}
