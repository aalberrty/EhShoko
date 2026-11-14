@testable import EhFeatures
import EhModels
import EhNetworking
import EhTestSupport
import Foundation
import Testing

@Suite struct GalleryReadingStatusTests {
    @Test func statusFollowsTheProgressAndThePageCount() {
        #expect(GalleryReadingStatus(progress: 0, pageCount: 48) == .unread)
        #expect(GalleryReadingStatus(progress: -1, pageCount: 48) == .unread)
        #expect(GalleryReadingStatus(progress: 1, pageCount: 48) == .inProgress(page: 1))
        #expect(GalleryReadingStatus(progress: 23, pageCount: 48) == .inProgress(page: 23))
        #expect(GalleryReadingStatus(progress: 48, pageCount: 48) == .finished)
        #expect(GalleryReadingStatus(progress: 50, pageCount: 48) == .finished)
        #expect(GalleryReadingStatus(progress: 1, pageCount: 1) == .finished)
        // An unknown page count is never finished.
        #expect(GalleryReadingStatus(progress: 5, pageCount: 0) == .inProgress(page: 5))
    }
}

/// Unread, in progress or finished, and what the Read button opens.
@MainActor
@Suite struct GalleryDetailReadingTests {
    private func model(progress: Int?, _ env: DetailEnvironment) async throws -> GalleryDetailModel {
        if let progress {
            try await env.database.updateReadingProgress(gid: DetailEnvironment.gid, progress: progress)
        }
        let model = env.makeDetailModel()
        await model.load()
        return model
    }

    @Test func unreadUntilTheProgressIsKnown() async throws {
        let env = try await DetailEnvironment()
        let model = env.makeDetailModel()
        #expect(model.readingProgress == nil)
        #expect(model.readingStatus == .unread)
        await model.load()
        #expect(model.readingProgress == 0)
        #expect(model.readingStatus == .unread)
    }

    @Test func theStoredProgressGivesTheStatus() async throws {
        let env = try await DetailEnvironment()
        #expect(try await model(progress: 23, env).readingStatus == .inProgress(page: 23))
        // The list's 156 pages: the last one was shown.
        #expect(try await model(progress: 156, env).readingStatus == .finished)
    }

    @Test func theStatusFollowsWhatTheReaderWrites() async throws {
        let env = try await DetailEnvironment()
        let model = try await model(progress: 3, env)
        try await env.database.updateReadingProgress(gid: DetailEnvironment.gid, progress: 40)
        await waitUntil { model.readingProgress == 40 }
        #expect(model.readingStatus == .inProgress(page: 40))
        try await env.database.updateReadingProgress(gid: DetailEnvironment.gid, progress: 156)
        await waitUntil { model.readingStatus == .finished }
        #expect(model.readingStatus == .finished)
    }

    @Test func readOpensWhereTheStatusSays() async throws {
        let env = try await DetailEnvironment()
        let unread = try await model(progress: nil, env)
        unread.read()
        #expect(unread.destination == .reader(page: nil))

        let started = try await model(progress: 23, env)
        started.read()
        #expect(started.destination == .reader(page: nil))
    }

    /// "Read again" starts from page 1, which becomes the stored progress.
    @Test func aFinishedGalleryIsReadAgainFromTheStart() async throws {
        let env = try await DetailEnvironment()
        let model = try await model(progress: 156, env)
        model.read()
        #expect(model.destination == .reader(page: 1))
        await waitUntil { model.readingProgress == 1 }
        #expect(try await env.database.readingState(gid: DetailEnvironment.gid)?.readingProgress == 1)
    }

    @Test func commentsIntentWithoutACommentOpensTheComments() async throws {
        let env = try await DetailEnvironment()
        let model = env.makeDetailModel(intent: .comments(scrollTo: nil))
        await model.load()
        await waitUntil { model.destination != nil }
        #expect(model.destination == .comments(scrollTo: nil))
        #expect(DetailIntent(.comment("42")) == .comments(scrollTo: "42"))
    }
}

/// The one-tap Favourite and the folder menu on the gallery page.
@MainActor
@Suite struct GalleryDetailFavoriteTests {
    private func loggedInModel(_ env: DetailEnvironment, reply: StubTransport.Reply = .status(200)) async
        -> GalleryDetailModel {
        env.logIn()
        env.transport.on(.method("POST"), reply: reply)
        return await env.loadedDetailModel()
    }

    private func favcat(_ env: DetailEnvironment) -> String? {
        env.requests("POST", path: "/gallerypopups.php").last.map(formBody)
    }

    @Test func oneTapFavouriteUsesTheLastFolderAndReportsIt() async throws {
        let env = try await DetailEnvironment()
        env.settings.lastFavoriteFolder = 2
        let model = await loggedInModel(env)

        model.quickFavorite()
        await model.lastOperation?.value
        #expect(favcat(env)?.contains("favcat=2") == true)
        #expect(model.favoriteReport == FavoriteReport(id: 1, gid: DetailEnvironment.gid, folder: 2, kind: .quick))
        #expect(model.feedback?.isSuccess == true)
    }

    @Test func theFolderMenuStoresTheFolder() async throws {
        let env = try await DetailEnvironment()
        let model = await loggedInModel(env)

        model.favorite(category: 7)
        await model.lastOperation?.value
        #expect(env.settings.lastFavoriteFolder == 7)
        #expect(model.favoriteReport?.kind == .chosen)

        model.quickFavorite()
        await model.lastOperation?.value
        #expect(favcat(env)?.contains("favcat=7") == true)
        #expect(model.favoriteReport == FavoriteReport(id: 2, gid: DetailEnvironment.gid, folder: 7, kind: .quick))
    }

    @Test func aFailedFavouriteReportsNothing() async throws {
        let env = try await DetailEnvironment()
        env.settings.lastFavoriteFolder = 1
        let model = await loggedInModel(env, reply: .error(URLError(.notConnectedToInternet)))

        model.favorite(category: 5)
        await model.lastOperation?.value
        #expect(model.feedback?.isSuccess == false)
        #expect(model.favoriteReport == nil)
        #expect(env.settings.lastFavoriteFolder == 1)
    }
}

/// From `ui-overhaul` `c00e3dc2`: what the figures bar and the More menu ask of the model.
@MainActor
@Suite struct GalleryDetailDerivedTests {
    @Test func favoritedFollowsTheLoadedPage() async throws {
        let env = try await DetailEnvironment()
        let model = env.makeDetailModel()
        #expect(model.isFavorited == false)
        env.serveDetail()
        await model.load()
        #expect(model.detail?.isFavorited == false)
        #expect(model.isFavorited == false)
    }

    @Test func showAllPreviewsOnlyPastTheTwentyOnThePage() async throws {
        let env = try await DetailEnvironment()
        #expect(env.makeDetailModel().showsAllPreviews)
        let short = Gallery(
            gid: DetailEnvironment.gid, token: DetailEnvironment.token, title: "Short", rating: 0, tags: [],
            category: .misc, pageCount: 20, postedDate: .now, coverURL: nil, galleryURL: DetailEnvironment.galleryURL
        )
        #expect(env.makeDetailModel(gallery: short).showsAllPreviews == false)
    }

    @Test func similarGalleryKeywordWaitsForThePage() async throws {
        let env = try await DetailEnvironment()
        let model = env.makeDetailModel()
        #expect(model.similarGalleryKeyword == nil)
        env.serveDetail()
        await model.load()
        let detail = try #require(model.detail)
        #expect(model.similarGalleryKeyword == DetailSearchKeyword.similar(to: detail))
    }
}
