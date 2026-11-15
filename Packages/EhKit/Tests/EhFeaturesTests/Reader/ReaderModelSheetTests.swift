import EhCore
@testable import EhFeatures
import EhModels
import Foundation
import Testing

/// What a control sheet shows (Ledger's): the short title and the count of failed pages.
@Suite struct ReaderModelSheetTests {
    @Test func theShortTitleIsTheTitleWithoutItsGroups() async throws {
        let harness = try ReaderModelHarness()
        let gallery = Gallery(
            gid: harness.gid, token: harness.site.token,
            title: "(C103) [Mizuiro Atelier (Hoshino Kanae)] Yoake no Hakoniwa (Original) [English] [Digital]",
            rating: 4, tags: [], category: .doujinshi, pageCount: 100,
            postedDate: Date(timeIntervalSince1970: 0), coverURL: nil, galleryURL: harness.site.galleryURL
        )

        let model = harness.makeModel(gallery: gallery)

        #expect(model.shortTitle(prefersJapanese: false) == "Yoake no Hakoniwa")
        #expect(model.shortTitle(prefersJapanese: true) == "Yoake no Hakoniwa")
    }

    @Test func aTitleOutsideTheConventionIsShownWhole() async throws {
        let harness = try ReaderModelHarness()
        let model = harness.makeModel()

        #expect(model.shortTitle(prefersJapanese: false) == "Title")
    }

    @Test func theShortTitleFollowsTheTitleTheGalleryPageShows() async throws {
        let harness = try ReaderModelHarness()
        try await harness.storeDetail(previewConfig: .large(rows: 4), jpnTitle: "[サークル (作家)] 夜明けの箱庭 [DL版]")

        let model = await harness.startedModel()

        #expect(model.shortTitle(prefersJapanese: true) == "夜明けの箱庭")
        #expect(model.shortTitle(prefersJapanese: false) == "Title")
    }

    @Test func failedPagesAreCountedUntilTheyAreRetried() async throws {
        let harness = try ReaderModelHarness()
        let model = await harness.startedModel()
        #expect(model.failedPageCount == 0)

        // A page that cannot be resolved.
        harness.site.fail("page:2")
        model.pagesNeeded([1, 2])
        await readerEventually {
            model.pageState(at: 2) == .failed && model.pageState(at: 1) == .image(harness.site.image(1))
        }
        #expect(model.failedPageCount == 1)

        // A page whose image did not load.
        model.imageDidFail(page: 1)
        #expect(model.failedPageCount == 2)

        model.retry(page: 2)
        #expect(model.failedPageCount == 1)
        await readerEventually { model.pageState(at: 2) == .image(harness.site.image(2)) }
        #expect(model.failedPageCount == 1)

        model.retryAllFailedImages()
        #expect(model.failedPageCount == 0)
    }

    @Test func aPageThatFailedBothWaysCountsOnce() async throws {
        let harness = try ReaderModelHarness()
        let model = await harness.startedModel()
        model.pagesNeeded([3])
        await readerEventually { model.pageState(at: 3) == .image(harness.site.image(3)) }

        // Its image fails, and so does the other image server.
        model.imageDidFail(page: 3)
        harness.site.fail("reload:3")
        model.retry(page: 3)
        await readerEventually { model.pageState(at: 3) == .failed }
        #expect(model.failedPageCount == 1)
        model.imageDidFail(page: 3)
        #expect(model.failedPageCount == 1)

        // "Reload all pages" starts over.
        model.reloadAllImages()
        #expect(model.failedPageCount == 0)
    }
}
