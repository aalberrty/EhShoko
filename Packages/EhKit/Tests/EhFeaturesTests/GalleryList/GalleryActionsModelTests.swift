import Dependencies
import EhCore
@testable import EhFeatures
import EhModels
import EhNetworking
import Foundation
import Testing

@MainActor
@Suite struct GalleryActionsModelTests {
    private let settings = SettingsStore(defaults: UserDefaults(suiteName: "F5Tests-\(UUID().uuidString)")!)

    private func makeModel(_ env: ListTestEnvironment) -> GalleryActionsModel {
        withDependencies { $0.settings = settings } operation: {
            env.make { GalleryActionsModel() }
        }
    }

    private func favoriteRequests(_ env: ListTestEnvironment) -> [URLRequest] {
        env.transport.requests.filter { $0.url?.path() == "/gallerypopups.php" }
    }

    private func body(_ request: URLRequest) -> String {
        request.httpBody.flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    // MARK: Read

    @Test func readPublishesTheRequestAndRecordsTheGalleryInHistory() async throws {
        let env = try ListTestEnvironment()
        let model = makeModel(env)
        #expect(model.readingRequest == nil)

        let gallery = Gallery.stub("42", title: "Read from a list")
        model.read(gallery)
        #expect(model.readingRequest == ReadingRequest(gallery: gallery))
        #expect(model.readingRequest?.page == nil)

        await model.recording?.value
        let stored = try await env.database.gallery(gid: "42")
        #expect(stored?.title == "Read from a list")
        #expect(stored?.lastOpenDate != nil)

        model.readingRequest = nil
        #expect(model.readingRequest == nil)
    }

    @Test func readingAgainMovesTheGalleryToTheTopOfHistory() async throws {
        let env = try ListTestEnvironment()
        try await env.database.recordOpened(.stub("1"), at: Date(timeIntervalSince1970: 10))
        try await env.database.recordOpened(.stub("2"), at: Date(timeIntervalSince1970: 20))
        let model = makeModel(env)

        model.read(.stub("1"))
        await model.recording?.value

        let history = env.make { HistoryModel() }
        await history.refresh()
        #expect(history.entries.map(\.id) == ["1", "2"])
    }

    // MARK: Favourites

    @Test func oneTapFavouriteUsesTheLastFolderAndReportsIt() async throws {
        let env = try ListTestEnvironment()
        env.transport.on(.method("POST"), reply: .status(200))
        settings.lastFavoriteFolder = 4
        let model = makeModel(env)

        model.favorite(.stub("7"))
        await model.lastOperation?.value

        let request = try #require(favoriteRequests(env).first)
        #expect(request.url?.query?.contains("act=addfav") == true)
        #expect(request.url?.query?.contains("gid=7") == true)
        #expect(body(request).contains("favcat=4"))
        #expect(model.favoriteReport == FavoriteReport(id: 1, gid: "7", folder: 4, kind: .quick))
        #expect(model.favoriteReport?.isQuick == true)
        #expect(model.favoriteChanges == ["7": .added(folder: 4)])
        #expect(model.feedback?.kind == .success)
        #expect(settings.lastFavoriteFolder == 4)
    }

    @Test func aChosenFolderIsStoredForTheNextOneTapFavourite() async throws {
        let env = try ListTestEnvironment()
        env.transport.on(.method("POST"), reply: .status(200))
        let model = makeModel(env)

        model.favorite(.stub("7"), folder: 6)
        await model.lastOperation?.value
        #expect(settings.lastFavoriteFolder == 6)
        #expect(model.favoriteReport?.kind == .chosen)
        #expect(model.favoriteReport?.folder == 6)

        model.favorite(.stub("8"))
        await model.lastOperation?.value
        #expect(body(try #require(favoriteRequests(env).last)).contains("favcat=6"))
        #expect(model.favoriteReport == FavoriteReport(id: 2, gid: "8", folder: 6, kind: .quick))
    }

    @Test func movingChangesTheFolderButNotTheStoredOne() async throws {
        let env = try ListTestEnvironment()
        env.transport.on(.method("POST"), reply: .status(200))
        settings.lastFavoriteFolder = 1
        let model = makeModel(env)
        let entry = GalleryEntry(gallery: .stub("7"), favorite: FavoriteMark(folder: 2))
        #expect(model.favoriteFolder(of: entry) == 2)

        model.move(entry.gallery, to: 5)
        await model.lastOperation?.value
        #expect(body(try #require(favoriteRequests(env).first)).contains("favcat=5"))
        #expect(model.favoriteFolder(of: entry) == 5)
        #expect(model.favoriteReport?.kind == .moved)
        #expect(settings.lastFavoriteFolder == 1)
    }

    @Test func unfavouriteRemovesTheMark() async throws {
        let env = try ListTestEnvironment()
        env.transport.on(.method("POST"), reply: .status(200))
        let model = makeModel(env)
        let entry = GalleryEntry(gallery: .stub("7"), favorite: FavoriteMark(folder: 2))

        model.unfavorite(entry.gallery)
        await model.lastOperation?.value
        let request = try #require(env.transport.requests.first { $0.url?.path() == "/favorites.php" })
        #expect(body(request).contains("modifygids%5B%5D=7"))
        #expect(model.favoriteFolder(of: entry) == nil)
        #expect(model.favoriteChanges == ["7": .removed])
        #expect(model.favoriteReport == nil)
    }

    @Test func aFailureChangesNothing() async throws {
        let env = try ListTestEnvironment()
        env.transport.on(.method("POST"), reply: .error(URLError(.notConnectedToInternet)))
        settings.lastFavoriteFolder = 3
        let model = makeModel(env)
        let entry = GalleryEntry(gallery: .stub("7"), favorite: FavoriteMark(folder: 2))

        model.favorite(entry.gallery, folder: 8)
        await model.lastOperation?.value
        #expect(model.feedback?.kind == .failure)
        #expect(settings.lastFavoriteFolder == 3)
        #expect(model.favoriteReport == nil)
        #expect(model.favoriteChanges.isEmpty)
        #expect(model.favoriteFolder(of: entry) == 2)

        model.unfavorite(entry.gallery)
        await model.lastOperation?.value
        #expect(model.favoriteFolder(of: entry) == 2)
    }

    @Test func aCancelledRequestIsIgnored() async throws {
        let env = try ListTestEnvironment()
        env.transport.on(.method("POST"), reply: .suspendUntilCancelled)
        let model = makeModel(env)

        model.favorite(.stub("7"))
        await waitUntil { !favoriteRequests(env).isEmpty }
        model.tasks.cancel("favorite-7")
        await model.lastOperation?.value
        #expect(model.feedback == nil)
        #expect(model.favoriteReport == nil)
        #expect(model.favoriteChanges.isEmpty)
    }

    @Test func signedOutNothingIsSent() async throws {
        let env = try ListTestEnvironment(loggedIn: false)
        let model = makeModel(env)
        #expect(!model.isLoggedIn)
        model.favorite(.stub("7"))
        model.unfavorite(.stub("7"))
        #expect(model.lastOperation == nil)
        #expect(env.transport.requests.isEmpty)
    }

    @Test func aFolderOutsideTheTenIsNotSent() async throws {
        let env = try ListTestEnvironment()
        let model = makeModel(env)
        model.favorite(.stub("7"), folder: 10)
        #expect(model.lastOperation == nil)
    }
}
