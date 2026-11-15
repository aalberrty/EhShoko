import EhCore
import EhDatabase
@testable import EhFeatures
import EhModels
import Foundation
import Observation
import Synchronization
import Testing

/// What the controls and the page status views show of the page states: why a page failed,
/// how many have, whether the current page has its image, and the parsed title.
@Suite struct ReaderModelPageSummaryTests {
    // MARK: Failure reason

    @Test func aPageThatCouldNotBeResolvedSaysWhy() async throws {
        let harness = try ReaderModelHarness()
        let model = await harness.startedModel()
        #expect(model.failureReason(at: 2) == nil)

        harness.site.fail("page:2")
        model.pagesNeeded([1, 2])
        await readerEventually { model.pageState(at: 2) == .failed }

        #expect(model.failureReason(at: 2) == .networkingFailed)
        #expect(model.failureReason(at: 1) == nil)

        model.retry(page: 2)
        #expect(model.failureReason(at: 2) == nil)
    }

    @Test func anImageThatDidNotLoadHasNoReasonFromTheModel() async throws {
        let harness = try ReaderModelHarness()
        let model = await harness.startedModel()
        model.pagesNeeded([3])
        await readerEventually { model.pageState(at: 3) == .image(harness.site.image(3)) }

        model.imageDidFail(page: 3)

        // The engine loads the images, so it knows why one failed.
        #expect(model.failureReason(at: 3) == nil)
        #expect(model.failedPageCount == 1)
    }

    // MARK: Failed-page count

    @Test func theFailedPageCountIsObservedWhenAPageFails() async throws {
        let harness = try ReaderModelHarness()
        let model = await harness.startedModel()
        let changes = ObservedChanges()

        changes.watch { _ = model.failedPageCount }
        harness.site.fail("page:2")
        model.pagesNeeded([1, 2])
        await readerEventually { model.pageState(at: 2) == .failed }

        #expect(changes.count == 1)
        #expect(model.failedPageCount == 1)
    }

    @Test func theEnginesReadOfTheCountIsNotObserved() async throws {
        let harness = try ReaderModelHarness()
        let model = await harness.startedModel()
        let changes = ObservedChanges()

        // The engine reads the count while SwiftUI makes it; an observed read would tie the
        // engine's updates to every failure.
        changes.watch { _ = model.pageSummary }
        harness.site.fail("page:2")
        model.pagesNeeded([1, 2])
        await readerEventually { model.pageState(at: 2) == .failed }

        #expect(model.pageSummary.failedPageCount == 1)
        #expect(model.pageSummary.currentPageHasImage)
        #expect(changes.count == 0)
    }

    @Test func pagesThatResolveLeaveTheFailedPageCountAlone() async throws {
        let harness = try ReaderModelHarness()
        let model = await harness.startedModel()
        let changes = ObservedChanges()

        changes.watch { _ = model.failedPageCount }
        model.pagesNeeded([1, 2, 3, 4])
        await readerEventually { (1...4).allSatisfy { model.pageState(at: $0) == .image(harness.site.image($0)) } }
        for page in 1...4 {
            model.imageDidLoad(page: page, pixelSize: CGSize(width: 1_280, height: 1_810))
        }

        #expect(changes.count == 0)
        #expect(model.failedPageCount == 0)
    }

    @Test func reloadingAllFailedPagesClearsTheCountAndReloadsEach() async throws {
        let harness = try ReaderModelHarness()
        let model = await harness.startedModel()
        harness.site.fail("page:2")
        model.pagesNeeded([1, 2, 3])
        await readerEventually {
            model.pageState(at: 2) == .failed && model.pageState(at: 3) == .image(harness.site.image(3))
        }
        model.imageDidFail(page: 3)
        #expect(model.failedPageCount == 2)
        harness.clearEngineLog()

        model.retryAllFailedImages()

        #expect(model.failedPageCount == 0)
        #expect(harness.engineCount("reload:2") == 1)
        #expect(harness.engineCount("reload:3") == 1)
        await readerEventually { model.pageState(at: 2) == .image(harness.site.image(2)) }
        #expect(model.failedPageCount == 0)
    }

    @Test func aPageReloadFromItsMenuLeavesTheCount() async throws {
        let harness = try ReaderModelHarness()
        let model = await harness.startedModel()
        model.pagesNeeded([3])
        await readerEventually { model.pageState(at: 3) == .image(harness.site.image(3)) }
        model.imageDidFail(page: 3)
        #expect(model.failedPageCount == 1)

        model.perform(.reload, page: 3)

        #expect(model.failedPageCount == 0)
    }

    // MARK: Current page has its image

    @Test func theCurrentPageHasItsImageOnceItResolves() async throws {
        let harness = try ReaderModelHarness()
        let model = await harness.startedModel()
        #expect(!model.currentPageHasImage)
        let changes = ObservedChanges()

        changes.watch { _ = model.currentPageHasImage }
        model.pagesNeeded([1, 2])
        await readerEventually { model.pageState(at: 2) == .image(harness.site.image(2)) }

        #expect(model.currentPageHasImage)
        // Page 2 resolving is not the current page's news.
        #expect(changes.count == 1)
    }

    @Test func turningToAPageWithoutItsImageClearsIt() async throws {
        let harness = try ReaderModelHarness()
        let model = await harness.startedModel()
        model.pagesNeeded([1])
        await readerEventually { model.currentPageHasImage }

        model.currentPageDidChange(50)
        #expect(!model.currentPageHasImage)

        model.currentPageDidChange(1)
        #expect(model.currentPageHasImage)
    }

    @Test func aStoredImageCountsFromTheStart() async throws {
        let harness = try ReaderModelHarness()
        try await harness.database.upsertPages([
            GalleryPage(gid: harness.gid, index: 4, imageURL: harness.site.image(4))
        ])

        let model = await harness.startedModel(initialPage: 4)

        #expect(model.currentPageHasImage)
    }

    @Test func reloadingAllImagesForgetsTheCurrentImage() async throws {
        let harness = try ReaderModelHarness()
        let model = await harness.startedModel()
        model.pagesNeeded([1])
        await readerEventually { model.currentPageHasImage }

        model.reloadAllImages()

        #expect(!model.currentPageHasImage)
    }

    // MARK: Parsed title

    @Test func theTitleIsParsedWhenTheReaderStarts() async throws {
        let harness = try ReaderModelHarness()
        let gallery = Gallery(
            gid: harness.gid, token: harness.site.token,
            title: "(C103) [Mizuiro Atelier (Hoshino Kanae)] Yoake no Hakoniwa (Original) [English] [Digital]",
            rating: 4, tags: [], category: .doujinshi, pageCount: 100,
            postedDate: Date(timeIntervalSince1970: 0), coverURL: nil, galleryURL: harness.site.galleryURL
        )
        let model = harness.makeModel(gallery: gallery)
        #expect(model.parsedTitles == nil)
        // Until then, the whole title.
        #expect(model.parsedTitle(prefersJapanese: false) == ParsedTitle(raw: gallery.title))

        await model.start()

        let parsed = model.parsedTitle(prefersJapanese: false)
        #expect(parsed.core == "Yoake no Hakoniwa")
        #expect(parsed.circle == "Mizuiro Atelier")
        #expect(parsed.artists == ["Hoshino Kanae"])
        #expect(model.parsedTitle(prefersJapanese: true) == parsed)
    }

    @Test func theParsedTitleIsTheDetailsOnceKnown() async throws {
        let harness = try ReaderModelHarness()
        try await harness.storeDetail(previewConfig: .large(rows: 4), jpnTitle: "[サークル (作家)] 夜明けの箱庭 [DL版]")

        let model = await harness.startedModel()

        #expect(model.parsedTitle(prefersJapanese: true).core == "夜明けの箱庭")
        #expect(model.parsedTitle(prefersJapanese: true).circle == "サークル")
        #expect(model.parsedTitle(prefersJapanese: false).core == "Title")
    }
}

/// Counts how often what `watch` reads is written, following it from one write to the next.
/// The model writes its summaries only when they change, so this counts changes.
private final class ObservedChanges: Sendable {
    private let changes = Mutex(0)

    var count: Int { changes.withLock { $0 } }

    func watch(_ read: @escaping @MainActor @Sendable () -> Void) {
        withObservationTracking {
            read()
        } onChange: { [self] in
            changes.withLock { $0 += 1 }
            // Called on the main actor, before the write: reading again follows the next one.
            MainActor.assumeIsolated { watch(read) }
        }
    }
}
