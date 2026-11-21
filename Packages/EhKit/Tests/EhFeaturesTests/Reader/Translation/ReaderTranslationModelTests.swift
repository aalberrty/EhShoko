import CoreGraphics
import EhCore
@testable import EhFeatures
import EhModels
import Foundation
import Testing

/// When a reader asks the service for pages: off until Translate is pressed, the download
/// sheet without models, and nothing after the reader closed.
@Suite struct ReaderTranslationModelTests {
    @Test func aNewReaderIsOffAndAsksTheServiceForNothing() async throws {
        let harness = try ReaderTranslationHarness()
        try await harness.models.installDefaultSet()
        try await harness.storeImageURLs()
        let model = await harness.openedModel(initialPage: 3)
        model.currentPageDidChange(4)
        await readerSettle()

        #expect(!model.translation.isOn)
        #expect(model.translation.status == nil)
        #expect(model.translationDisplay == .original)
        #expect(harness.service.opened.isEmpty)
        #expect(harness.service.windows.isEmpty)
        #expect(harness.log.isEmpty)
        #expect(model.translationAvailability == .ready)
    }

    @Test func beforeTheFirstPageTheStoreIsNotEvenLookedAt() async throws {
        let harness = try ReaderTranslationHarness()
        let model = harness.makeModel()
        await model.start()
        await readerSettle()

        // Not loaded, and not asked to load: the press reads the folder when it comes.
        #expect(!harness.models.store.isLoaded)
        #expect(model.translationAvailability == .ready)
        #expect(model.translation.pagesTranslatedBefore == 0)

        model.imageDidLoad(page: 1, pixelSize: CGSize(width: 800, height: 1200))
        await readerSettle()
        #expect(!harness.models.store.isLoaded)
        #expect(harness.models.transport.requests.isEmpty)
    }

    @Test func theCountForTheMarkIsReadOnceAfterTheFirstPage() async throws {
        let harness = try ReaderTranslationHarness()
        try await harness.models.installDefaultSet()
        try await harness.storeTranslations(of: [2, 3, 5])
        let model = harness.makeModel()
        await model.start()
        await readerSettle()
        #expect(model.translation.pagesTranslatedBefore == 0)

        model.imageDidLoad(page: 1, pixelSize: CGSize(width: 800, height: 1200))
        await readerEventually { model.translation.pagesTranslatedBefore == 3 }

        // Read once: a page translated meanwhile does not change the mark.
        try await harness.storeTranslations(of: [7])
        model.currentPageDidChange(2)
        model.imageDidLoad(page: 2, pixelSize: CGSize(width: 800, height: 1200))
        await readerSettle()
        #expect(model.translation.pagesTranslatedBefore == 3)
        #expect(harness.service.opened.isEmpty)
    }

    @Test func aSecondReaderOfTheSameGalleryIsOffAgainAndShowsTheCount() async throws {
        let harness = try ReaderTranslationHarness()
        try await harness.models.installDefaultSet()
        try await harness.storeImageURLs()
        let first = await harness.openedModel()
        first.toggleTranslation()
        await readerEventually { first.translation.isOn }
        try await harness.storeTranslations(of: [1, 2])
        first.close()

        let second = await harness.openedModel()
        await readerEventually { second.translation.pagesTranslatedBefore == 2 }
        #expect(!second.translation.isOn)
        #expect(harness.service.opened.count == 1)
    }

    @Test func aPressTurnsTranslateOnAndAsksForThePagesAroundTheCurrentOne() async throws {
        let harness = try ReaderTranslationHarness()
        try await harness.models.installDefaultSet()
        try await harness.storeImageURLs()
        let model = await harness.openedModel(initialPage: 5)

        model.toggleTranslation()
        await readerEventually { model.translation.isOn }

        #expect(harness.service.opened == [harness.gid])
        let window = try #require(harness.service.lastWindow)
        #expect(window.onScreen == [PageTranslationPage(index: 5, imageURL: harness.image(5))])
        #expect(window.ahead.map(\.index) == [6, 7, 8])
        #expect(window.behind.map(\.index) == [4])
        #expect(model.translationDisplay == .translated)
        #expect(harness.log == ["display:translated"])
        #expect(model.destination == nil)
    }

    @Test func storedPagesAreShownBeforeTheModelsHaveLoaded() async throws {
        let harness = try ReaderTranslationHarness()
        try await harness.models.installDefaultSet()
        try await harness.storeImageURLs()
        let model = await harness.openedModel(initialPage: 5)
        model.toggleTranslation()
        await readerEventually { harness.service.lastWindow != nil }
        harness.clearLog()

        // The service reports a stored page at once, while the others wait for the models.
        harness.service.yield(6, .loadingModels)
        harness.service.yield(5, .translated(ReaderTranslationHarness.overlay(5)))
        await readerEventually { model.translation.status == .translated }

        #expect(model.translationOverlay(at: 5) == ReaderTranslationHarness.overlay(5))
        #expect(harness.log == ["translation:5"])
        model.currentPageDidChange(6)
        #expect(model.translation.status == .gettingReady)
    }

    @Test func aPressWithoutModelsOpensTheDownloadAndStartsWhenTheInstallEnds() async throws {
        let harness = try ReaderTranslationHarness()
        try await harness.storeImageURLs()
        let model = await harness.openedModel()

        model.toggleTranslation()
        await readerEventually { model.destination == .translationDownload }
        #expect(model.translation.isWaitingForModels)
        #expect(!model.translation.isOn)
        #expect(harness.service.opened.isEmpty)
        #expect(model.translationAvailability == .needsModels)

        // The sheet's button; the download belongs to the store.
        harness.models.store.downloadRequiredModels()
        await readerEventually { model.translation.isOn }
        #expect(harness.service.opened == [harness.gid])
        #expect(harness.service.lastWindow?.onScreen.map(\.index) == [1])
        #expect(!model.translation.isWaitingForModels)
    }

    @Test func anInstallThatEndsAfterTheReaderClosedStartsNothing() async throws {
        let harness = try ReaderTranslationHarness()
        try await harness.storeImageURLs()
        harness.models.hold(.k2xl)
        let model = await harness.openedModel()
        model.toggleTranslation()
        await readerEventually { model.destination == .translationDownload }
        harness.models.store.downloadRequiredModels()
        await waitFor("the detector is being fetched") { harness.models.isWaiting(.k2xl) }
        guard case .installing = model.translationAvailability else {
            Issue.record("A download under way is `.installing`, not \(model.translationAvailability)")
            return
        }

        model.close()
        harness.models.release(.k2xl)
        await waitFor("the models are installed") { harness.models.store.requiredModelsState == .ready }
        await readerSettle()

        #expect(harness.service.opened.isEmpty)
        #expect(!model.translation.isOn)
        #expect(!model.translation.isWaitingForModels)
    }

    @Test func nothingIsAskedOnTheClosingPage() async throws {
        let harness = try ReaderTranslationHarness()
        try await harness.models.installDefaultSet()
        try await harness.storeImageURLs()
        let model = await harness.openedModel(initialPage: 10)
        model.toggleTranslation()
        await readerEventually { harness.service.lastWindow != nil }
        harness.service.yield(10, .translating)
        await readerEventually { model.translation.status == .translating(page: 10) }
        let windows = harness.service.windows.count

        model.trailerVisibilityDidChange(true)
        await readerSettle()

        #expect(harness.service.windows.count == windows)
        #expect(harness.service.windows.allSatisfy { $0.pages.allSatisfy { $0.index <= 10 } })
        #expect(model.translation.status == nil)
        model.trailerVisibilityDidChange(false)
        #expect(model.translation.status == .translating(page: 10))
    }

    @Test func closeCancelsEverything() async throws {
        let harness = try ReaderTranslationHarness()
        try await harness.models.installDefaultSet()
        try await harness.storeImageURLs()
        let model = await harness.openedModel(initialPage: 5)
        model.toggleTranslation()
        await readerEventually { harness.service.lastWindow != nil }
        harness.clearLog()
        let windows = harness.service.windows.count

        model.close()
        #expect(harness.service.closes == 1)

        harness.service.yield(5, .translated(ReaderTranslationHarness.overlay(5)))
        model.currentPageDidChange(6)
        model.toggleTranslation()
        await readerSettle()
        #expect(harness.log.isEmpty)
        #expect(harness.service.windows.count == windows)
        #expect(harness.service.opened.count == 1)
        #expect(harness.service.closes == 1)
    }

    @Test func theModelIsReleasedWithItsReader() async throws {
        let harness = try ReaderTranslationHarness()
        try await harness.models.installDefaultSet()
        try await harness.storeImageURLs()
        weak var reader: ReaderModel?
        weak var translation: ReaderTranslationModel?
        do {
            let model = await harness.openedModel()
            model.toggleTranslation()
            await readerEventually { model.translation.isOn }
            harness.service.yield(1, .translated(ReaderTranslationHarness.overlay(1)))
            await readerEventually { model.translation.status == .translated }
            reader = model
            translation = model.translation
            model.close()
        }
        await readerEventually { reader == nil && translation == nil }
    }

    @Test func aGalleryInAnotherLanguageOffersNoTranslate() async throws {
        let harness = try ReaderTranslationHarness()
        try await harness.models.installDefaultSet()
        try await harness.storeTranslations(of: [1])
        let site = harness.reader.site
        let english = Gallery(
            gid: site.gid, token: site.token, title: "[Circle (Artist)] Title [English]", rating: 4, tags: [],
            category: .doujinshi, pageCount: site.pageCount, postedDate: Date(timeIntervalSince1970: 0),
            coverURL: nil, galleryURL: site.galleryURL
        )
        let model = await harness.openedModel(gallery: english)
        await readerEventually { model.parsedTitles != nil }

        #expect(model.translationAvailability == .unavailable)
        model.toggleTranslation()
        await readerSettle()
        #expect(harness.service.opened.isEmpty)
        #expect(model.destination == nil)
        // No control, so no mark: the count was not read.
        #expect(model.translation.pagesTranslatedBefore == 0)
    }
}
