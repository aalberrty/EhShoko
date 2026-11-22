import EhCore
@testable import EhFeatures
import EhModels
import Testing

/// `failedPageOnScreen`: the warning mark on Ledger's resting Translate button, shown while a
/// page on screen has failed and gone when the page is translated, left, or Translate is off.
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
        // The current page's own status is unchanged: it is translated.
        #expect(model.translation.status == .translated)

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
}
