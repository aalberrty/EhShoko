@testable import EhFeatures
import EhModels
import EhTestSupport
import Foundation
import Testing

/// When a reader presented over a list closes, the list reads its rows' progress again.
@MainActor
@Suite struct ReadingProgressRefreshTests {
    @Test func refreshPicksUpProgressMadeWhileReading() async throws {
        let env = try ListTestEnvironment()
        env.transport.on(.any, reply: .fixture(ListFixture.frontpage))
        let model = env.make { GalleryListModel(source: .frontpage) }
        await model.loadIfNeeded()
        let before = model.entries
        let requests = env.transport.requests.count

        try await env.database.updateReadingProgress(gid: ListFixture.frontpageLastID, progress: 5)
        await model.refreshReadingProgress()

        #expect(model.entries.first { $0.id == ListFixture.frontpageLastID }?.readingProgress == 5)
        #expect(model.entries.map(\.id) == before.map(\.id))
        // Only the read row changed; the others are the same values, and nothing was fetched.
        let others = zip(model.entries, before).filter { $0.0.id != ListFixture.frontpageLastID }
        #expect(others.allSatisfy { $0.0 == $0.1 })
        #expect(env.transport.requests.count == requests)
    }

    @Test func refreshWithoutChangesLeavesTheRowsAlone() async throws {
        let env = try ListTestEnvironment()
        env.transport.on(.any, reply: .fixture(ListFixture.frontpage))
        try await env.database.updateReadingProgress(gid: ListFixture.frontpageLastID, progress: 2)
        let model = env.make { GalleryListModel(source: .frontpage) }
        await model.loadIfNeeded()
        let before = model.entries

        await model.refreshReadingProgress()
        #expect(model.entries == before)

        // Progress set back to the start is no longer shown.
        try await env.database.updateReadingProgress(gid: ListFixture.frontpageLastID, progress: 0)
        await model.refreshReadingProgress()
        #expect(model.entries.allSatisfy { $0.readingProgress == nil })
    }

    @Test func anEmptyListReadsNothing() async throws {
        let env = try ListTestEnvironment()
        let model = env.make { GalleryListModel(source: .frontpage) }

        await model.refreshReadingProgress()
        #expect(model.entries.isEmpty)
        #expect(env.transport.requests.isEmpty)
    }

    /// A list replaced while the progress is read (a reload) keeps its new rows.
    @Test func aReplacedListIsNotOverwritten() async throws {
        let env = try ListTestEnvironment()
        env.transport.on(.any, reply: .fixture(ListFixture.frontpage))
        let model = env.make { GalleryListModel(source: .frontpage) }
        await model.loadIfNeeded()
        try await env.database.updateReadingProgress(gid: ListFixture.frontpageLastID, progress: 9)

        let refresh = Task { await model.refreshReadingProgress() }
        // Lets the refresh start its read before the list is replaced.
        await Task.yield()
        model.reload()
        await refresh.value
        #expect(model.entries.isEmpty)
    }
}
