import Dependencies
import EhDatabase
@testable import EhFeatures
import EhModels
import Foundation
import Observation
import Synchronization
import Testing

@Suite struct ContinueModelTests {
    private func gallery(_ gid: String, pages: Int = 48) -> Gallery {
        Gallery(
            gid: gid, token: "t\(gid)", title: "Title \(gid)", rating: 4, tags: [], category: .manga,
            uploader: nil, pageCount: pages, postedDate: Date(timeIntervalSince1970: 0),
            coverURL: nil, galleryURL: nil
        )
    }

    private func open(_ gid: String, at seconds: Double, page: Int?, in database: AppDatabase) async throws {
        try await database.recordOpened(gallery(gid), at: Date(timeIntervalSince1970: seconds))
        if let page { try await database.updateReadingProgress(gid: gid, progress: page) }
    }

    @Test func followsTheGalleriesInProgress() async throws {
        let env = try ListTestEnvironment()
        try await open("1", at: 10, page: 23, in: env.database)
        try await open("2", at: 20, page: nil, in: env.database)
        let model = env.make { ContinueModel() }
        #expect(model.loadingState == .loading)
        #expect(model.items.isEmpty && model.first == nil)

        let task = Task { await model.observe() }
        await waitUntil { model.loadingState == .idle }
        #expect(model.items.map(\.id) == ["1"])
        #expect(model.first == ContinueItem(
            gallery: gallery("1").withOpenDate(10), page: 23, pageCount: 48
        ))
        #expect(model.first?.fraction == 23.0 / 48)

        // Reading the second gallery puts it first.
        try await env.database.updateReadingProgress(gid: "2", progress: 5)
        try await env.database.recordOpened(gallery("2"), at: Date(timeIntervalSince1970: 30))
        await waitUntil { model.first?.id == "2" }
        #expect(model.items.map(\.id) == ["2", "1"])

        // Finishing it takes it out: Continue shows the next unfinished gallery.
        try await env.database.updateReadingProgress(gid: "2", progress: 48)
        await waitUntil { model.items.count == 1 }
        #expect(model.first?.id == "1")

        try await env.database.clearHistory()
        await waitUntil { model.items.isEmpty }
        #expect(model.first == nil)
        #expect(model.loadingState == .idle)
        task.cancel()
        await task.value
        #expect(model.loadingState == .idle)
    }

    @Test func theLimit() async throws {
        let env = try ListTestEnvironment()
        for index in 1...12 {
            try await open("\(index)", at: Double(index), page: 2, in: env.database)
        }
        let model = env.make { ContinueModel() }
        let task = Task { await model.observe() }
        await waitUntil { model.loadingState == .idle }
        #expect(model.items.count == ContinueModel.defaultLimit)
        #expect(model.first?.id == "12")
        task.cancel()

        let small = env.make { ContinueModel(limit: 3) }
        let smallTask = Task { await small.observe() }
        await waitUntil { small.loadingState == .idle }
        #expect(small.items.map(\.id) == ["12", "11", "10"])
        smallTask.cancel()
    }

    @Test func emptyHistory() async throws {
        let env = try ListTestEnvironment()
        let model = env.make { ContinueModel() }
        let task = Task { await model.observe() }
        await waitUntil { model.loadingState == .idle }
        #expect(model.items.isEmpty)
        #expect(model.first == nil)
        task.cancel()
    }

    /// A view showing only the first gallery is not invalidated when another one changes.
    @Test func aChangeBehindTheFirstLeavesFirstAlone() async throws {
        let env = try ListTestEnvironment()
        try await open("1", at: 1, page: 3, in: env.database)
        try await open("2", at: 2, page: 4, in: env.database)
        let model = env.make { ContinueModel() }
        let task = Task { await model.observe() }
        await waitUntil { model.items.count == 2 }

        let firstChanged = Flag()
        withObservationTracking { _ = model.first } onChange: { firstChanged.set() }
        try await env.database.updateReadingProgress(gid: "1", progress: 9)
        await waitUntil { model.items.last?.page == 9 }
        #expect(model.items.last?.page == 9)
        #expect(!firstChanged.value)
        task.cancel()
    }

    @Test func itemsCarryTheParsedTitle() async {
        let raw = "(C102) [Circle (Artist)] Title (Parody) [English]"
        let row = ReadingListItem(gallery: gallery("1").retitled(raw), page: 3, pageCount: 48)

        let items = await ContinueModel.items(from: [row])
        #expect(items.first?.title.core == "Title")
        #expect(items.first?.title.artists == ["Artist"])

        // A page turn sends the row again: the title is reused, and a renamed gallery parsed again.
        let turned = ReadingListItem(gallery: row.gallery, page: 4, pageCount: 48)
        #expect(await ContinueModel.items(from: [turned], reusing: items).first?.title == items.first?.title)
        let renamed = ReadingListItem(gallery: gallery("1").retitled("[Other] Name"), page: 4, pageCount: 48)
        #expect(await ContinueModel.items(from: [renamed], reusing: items).first?.title.core == "Name")
    }
}

private extension Gallery {
    func retitled(_ title: String) -> Gallery {
        var gallery = self
        gallery.title = title
        return gallery
    }

    func withOpenDate(_ seconds: Double) -> Gallery {
        Gallery(
            gid: gid, token: token, title: title, rating: rating, tags: tags, category: category,
            uploader: uploader, pageCount: pageCount, postedDate: postedDate, coverURL: coverURL,
            galleryURL: galleryURL, lastOpenDate: Date(timeIntervalSince1970: seconds)
        )
    }
}

private nonisolated final class Flag: Sendable {
    private let state = Mutex(false)
    func set() { state.withLock { $0 = true } }
    var value: Bool { state.withLock { $0 } }
}
