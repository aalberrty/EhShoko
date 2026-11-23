import EhCore
@testable import EhFeatures
import EhModels
import Testing

/// `failedPagesOnScreen` and the status it gives: Ledger's warning mark, every design's line
/// with Try again for a failure of any page on screen, and what Try again asks for.
@Suite struct ReaderTranslationFailedOnScreenTests {
    private func translatingModel(_ harness: ReaderTranslationHarness, page: Int) async throws -> ReaderModel {
        try await harness.models.installDefaultSet()
        try await harness.storeImageURLs()
        let model = await harness.openedModel(initialPage: page)
        model.toggleTranslation()
        await readerEventually { model.translation.isOn }
        return model
    }

    @Test func aFailedCurrentPageIsMarkedUntilRetryTranslatesIt() async throws {
        let harness = try ReaderTranslationHarness()
        let model = try await translatingModel(harness, page: 5)
        #expect(model.translation.failedPageOnScreen == nil)

        harness.service.yield(5, .failed(.pipelineFailed))
        await readerEventually { model.translation.failedPageOnScreen == 5 }

        // Try again: the page is asked for again and is no longer failed.
        model.retryTranslation()
        #expect(model.translation.failedPageOnScreen == nil)
        harness.service.yield(5, .translated(ReaderTranslationHarness.overlay(5)))
        await readerEventually { model.translation.status == .translated }
        #expect(model.translation.failedPageOnScreen == nil)
    }

    @Test func theOtherPageOfASpreadIsMarkedAndLeavingItClearsTheMark() async throws {
        let harness = try ReaderTranslationHarness()
        let model = try await translatingModel(harness, page: 4)
        model.pagesOnScreenDidChange([4, 5])

        harness.service.yield(4, .translated(ReaderTranslationHarness.overlay(4)))
        harness.service.yield(5, .failed(.pipelineFailed))
        await readerEventually { model.translation.failedPageOnScreen == 5 }
        // The current page is translated and has nothing to say: the line names page 5.
        #expect(model.translation.status == .failed(page: 5))

        // A turn of the spread, as the engine reports it: the pages, then the current page.
        model.pagesOnScreenDidChange([6, 7])
        model.currentPageDidChange(6)
        #expect(model.translation.failedPageOnScreen == nil)

        // Back again: page 5 stayed in the window, behind, so its failure is still known.
        model.pagesOnScreenDidChange([4, 5])
        model.currentPageDidChange(4)
        #expect(model.translation.failedPageOnScreen == 5)
    }

    @Test func theNearestFailedPageIsNamed() async throws {
        let harness = try ReaderTranslationHarness()
        let model = try await translatingModel(harness, page: 4)
        model.pagesOnScreenDidChange([4, 5])

        harness.service.yield(5, .failed(.pipelineFailed))
        await readerEventually { model.translation.failedPageOnScreen == 5 }
        harness.service.yield(4, .failed(.pipelineFailed))
        await readerEventually { model.translation.failedPageOnScreen == 4 }
    }

    @Test func turningTranslateOffClearsTheMark() async throws {
        let harness = try ReaderTranslationHarness()
        let model = try await translatingModel(harness, page: 5)
        harness.service.yield(5, .failed(.pipelineFailed))
        await readerEventually { model.translation.failedPageOnScreen == 5 }

        model.toggleTranslation()
        #expect(!model.translation.isOn)
        #expect(model.translation.failedPageOnScreen == nil)
    }

    @Test func aPageWhoseOverlayCannotBeShownIsMarked() async throws {
        let harness = try ReaderTranslationHarness()
        let model = try await translatingModel(harness, page: 5)
        harness.service.yield(5, .translated(ReaderTranslationHarness.overlay(5)))
        await readerEventually { model.translationOverlay(at: 5) != nil }

        // Drawn again once, and the second drawing cannot be shown either.
        model.translationOverlayDidFail(page: 5)
        harness.service.yield(5, .translated(ReaderTranslationHarness.overlay(5, "v2")))
        await readerEventually { model.translationOverlay(at: 5) != nil }
        model.translationOverlayDidFail(page: 5)
        #expect(model.translation.failedPageOnScreen == 5)
    }

    @Test func theOtherPagesFailureWaitsWhileTheCurrentPageHasSomethingToSay() async throws {
        let harness = try ReaderTranslationHarness()
        let model = try await translatingModel(harness, page: 4)
        model.pagesOnScreenDidChange([4, 5])

        harness.service.yield(4, .translating)
        harness.service.yield(5, .failed(.pipelineFailed))
        await readerEventually { model.translation.failedPagesOnScreen == [5] }
        #expect(model.translation.status == .translating(page: 4))

        // Done: the other page's failure takes the line.
        harness.service.yield(4, .nothingToDraw)
        await readerEventually { model.translation.status == .failed(page: 5) }

        // The current page speaks again as soon as it has something to say.
        harness.service.yield(4, .loadingModels)
        await readerEventually { model.translation.status == .gettingReady }
        harness.service.yield(4, .failed(.pipelineFailed))
        await readerEventually { model.translation.status == .failed(page: 4) }
        #expect(model.translation.failedPagesOnScreen == [4, 5])
    }

    @Test func aSkippedCurrentPageGivesTheLineToTheOtherPage() async throws {
        let harness = try ReaderTranslationHarness()
        let model = try await translatingModel(harness, page: 4)
        model.pagesOnScreenDidChange([4, 5])

        harness.service.yield(4, .skipped)
        harness.service.yield(5, .failed(.pipelineFailed))
        await readerEventually { model.translation.status == .failed(page: 5) }
    }

    @Test func tryAgainAsksForEveryFailedPageOnScreen() async throws {
        let harness = try ReaderTranslationHarness()
        let model = try await translatingModel(harness, page: 4)
        model.pagesOnScreenDidChange([4, 5])
        harness.service.yield(4, .failed(.pipelineFailed))
        harness.service.yield(5, .failed(.pipelineFailed))
        await readerEventually { model.translation.failedPagesOnScreen == [4, 5] }

        model.retryTranslation()
        #expect(harness.service.retries == [4, 5])
        #expect(model.translation.failedPagesOnScreen.isEmpty)
        #expect(model.translation.status == .translating(page: 4))
    }

    @Test func tryAgainAsksForTheOtherPageAlone() async throws {
        let harness = try ReaderTranslationHarness()
        let model = try await translatingModel(harness, page: 4)
        model.pagesOnScreenDidChange([4, 5])
        harness.service.yield(4, .translated(ReaderTranslationHarness.overlay(4)))
        harness.service.yield(5, .failed(.pipelineFailed))
        await readerEventually { model.translation.status == .failed(page: 5) }

        model.retryTranslation()
        #expect(harness.service.retries == [5])
        // The current page is translated; the other page is in work, which is not its to say.
        #expect(model.translation.status == .translated)
        #expect(model.translation.failedPageOnScreen == nil)
    }

    @Test func tryAgainIncludesAnOtherPageWhoseOverlayCannotBeShown() async throws {
        let harness = try ReaderTranslationHarness()
        let model = try await translatingModel(harness, page: 4)
        model.pagesOnScreenDidChange([4, 5])
        harness.service.yield(4, .translated(ReaderTranslationHarness.overlay(4)))
        harness.service.yield(5, .translated(ReaderTranslationHarness.overlay(5)))
        await readerEventually { model.translationOverlay(at: 5) != nil }
        model.translationOverlayDidFail(page: 5)
        harness.service.yield(5, .translated(ReaderTranslationHarness.overlay(5, "v2")))
        await readerEventually { model.translationOverlay(at: 5) != nil }
        model.translationOverlayDidFail(page: 5)
        #expect(model.translation.status == .failed(page: 5))

        model.retryTranslation()
        #expect(harness.service.retries == [5, 5])
        #expect(model.translation.status == .translated)
    }

    @Test func aTurnAndTranslateOffClearTheOtherPagesFailure() async throws {
        let harness = try ReaderTranslationHarness()
        let model = try await translatingModel(harness, page: 4)
        model.pagesOnScreenDidChange([4, 5])
        harness.service.yield(4, .translated(ReaderTranslationHarness.overlay(4)))
        harness.service.yield(5, .failed(.pipelineFailed))
        await readerEventually { model.translation.status == .failed(page: 5) }

        model.pagesOnScreenDidChange([6, 7])
        model.currentPageDidChange(6)
        #expect(model.translation.status == nil)
        #expect(model.translation.failedPagesOnScreen.isEmpty)

        model.pagesOnScreenDidChange([4, 5])
        model.currentPageDidChange(4)
        #expect(model.translation.status == .failed(page: 5))
        model.toggleTranslation()
        #expect(model.translation.status == nil)
        #expect(model.translation.failedPagesOnScreen.isEmpty)
    }
}
