import EhCore
@testable import EhFeatures
import Testing

/// What the engine is given of the pages translated in a reader: nothing while Translate is
/// off, and a page whose overlay cannot be shown even after it was drawn again is marked
/// failed rather than shown as translated.
@Suite struct ReaderTranslationOverlayTests {
    /// A reader at page 5 with Translate on, page 5 translated, and the log cleared.
    private func translatedModel(_ harness: ReaderTranslationHarness) async throws -> ReaderModel {
        try await harness.models.installDefaultSet()
        try await harness.storeImageURLs()
        let model = await harness.openedModel(initialPage: 5)
        model.toggleTranslation()
        await readerEventually { model.translation.isOn }
        harness.service.yield(5, .translated(ReaderTranslationHarness.overlay(5)))
        await readerEventually { model.translation.status == .translated }
        harness.clearLog()
        return model
    }

    @Test func whileOffTheEngineIsGivenNoOverlay() async throws {
        let harness = try ReaderTranslationHarness()
        let model = try await translatedModel(harness)
        harness.service.yield(6, .translated(ReaderTranslationHarness.overlay(6)))
        await readerEventually { model.translationOverlay(at: 6) != nil }
        harness.clearLog()

        model.toggleTranslation()
        #expect(model.translationOverlay(at: 5) == nil)
        #expect(model.translationOverlay(at: 6) == nil)
        // Every translated page is asked about again, so its view lets the patches go.
        #expect(harness.log == ["display:original", "translation:5", "translation:6"])

        // On again: the same overlays, at once, before the service says anything.
        harness.clearLog()
        model.toggleTranslation()
        await readerEventually { model.translation.isOn }
        #expect(model.translationOverlay(at: 5) == ReaderTranslationHarness.overlay(5))
        #expect(model.translationOverlay(at: 6) == ReaderTranslationHarness.overlay(6))
        #expect(harness.log == ["display:translated", "translation:5", "translation:6"])
    }

    @Test func holdingTheOriginalKeepsTheOverlays() async throws {
        let harness = try ReaderTranslationHarness()
        let model = try await translatedModel(harness)

        model.translation.holdOriginal(true)
        #expect(model.translationDisplay == .original)
        #expect(model.translationOverlay(at: 5) == ReaderTranslationHarness.overlay(5))
        model.translation.holdOriginal(false)
        // Switching is the display alone: no page is asked about again.
        #expect(harness.log == ["display:original", "display:translated"])
    }

    @Test func aPageTranslatedWhileOffIsGivenWhenTurnedOn() async throws {
        let harness = try ReaderTranslationHarness()
        let model = try await translatedModel(harness)
        model.toggleTranslation()
        harness.clearLog()

        // A late event of the work that was going on.
        harness.service.yield(6, .translated(ReaderTranslationHarness.overlay(6)))
        await readerSettle()
        #expect(model.translationOverlay(at: 6) == nil)
        #expect(harness.log.isEmpty)

        model.toggleTranslation()
        await readerEventually { model.translation.isOn }
        #expect(model.translationOverlay(at: 6) == ReaderTranslationHarness.overlay(6))
        #expect(harness.log.contains("translation:6"))
    }

    @Test func aSecondFailureToShowAPageMarksItFailed() async throws {
        let harness = try ReaderTranslationHarness()
        let model = try await translatedModel(harness)

        // The first time, the page is drawn again.
        model.translationOverlayDidFail(page: 5)
        #expect(harness.service.retries == [5])
        #expect(model.translationOverlay(at: 5) == nil)
        harness.service.yield(5, .translating)
        harness.service.yield(5, .translated(ReaderTranslationHarness.overlay(5)))
        await readerEventually { model.translationOverlay(at: 5) != nil }
        #expect(model.translation.status == .translated)

        // The drawing again cannot be shown either: not drawn again by itself, and the page
        // says it failed instead of translated.
        model.translationOverlayDidFail(page: 5)
        #expect(harness.service.retries == [5])
        #expect(model.translationOverlay(at: 5) == nil)
        #expect(model.translation.status == .failed(page: 5))
        #expect(harness.log == ["translation:5", "translation:5", "translation:5"])

        // Another page and back: still failed.
        model.currentPageDidChange(6)
        #expect(model.translation.status == nil)
        model.currentPageDidChange(5)
        #expect(model.translation.status == .failed(page: 5))

        // Retry asks for it again and says so.
        model.retryTranslation()
        #expect(harness.service.retries == [5, 5])
        #expect(model.translation.status == .translating(page: 5))
        harness.service.yield(5, .translated(ReaderTranslationHarness.overlay(5)))
        await readerEventually { model.translation.status == .translated }
        // A third failure is marked failed again, still without a retry of its own.
        model.translationOverlayDidFail(page: 5)
        #expect(harness.service.retries == [5, 5])
        #expect(model.translation.status == .failed(page: 5))
    }

    @Test func turningOffClearsTheFailureButNotTheRedraw() async throws {
        let harness = try ReaderTranslationHarness()
        let model = try await translatedModel(harness)
        model.translationOverlayDidFail(page: 5)
        harness.service.yield(5, .translated(ReaderTranslationHarness.overlay(5)))
        await readerEventually { model.translationOverlay(at: 5) != nil }
        model.translationOverlayDidFail(page: 5)
        #expect(model.translation.status == .failed(page: 5))

        model.toggleTranslation()
        #expect(model.translation.status == nil)
        model.toggleTranslation()
        await readerEventually { model.translation.isOn }
        // The service still has the page; its file is given once more, and its failure is
        // marked at once, not drawn again in a circle.
        harness.service.yield(5, .translated(ReaderTranslationHarness.overlay(5)))
        await readerEventually { model.translationOverlay(at: 5) != nil }
        #expect(model.translation.status == .translated)
        model.translationOverlayDidFail(page: 5)
        #expect(harness.service.retries == [5])
        #expect(model.translation.status == .failed(page: 5))
    }
}
