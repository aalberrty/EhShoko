@testable import EhFeatures
import EhModels
import EhTestSupport
import Foundation
import Testing

/// Entries carry the stored reading progress of their gallery, read once per page mapped.
@MainActor
@Suite struct ReadingProgressEntriesTests {
    @Test func aListPageCarriesTheProgressOfItsGalleries() async throws {
        let env = try ListTestEnvironment()
        env.transport.on(.any, reply: .fixture(ListFixture.frontpage))
        try await env.database.updateReadingProgress(gid: ListFixture.frontpageLastID, progress: 12)
        try await env.database.updateReadingProgress(gid: "2668616", progress: 0)
        let model = env.make { GalleryListModel(source: .frontpage) }

        await model.loadIfNeeded()

        let started = model.entries.filter { $0.readingProgress != nil }
        #expect(started.map(\.id) == [ListFixture.frontpageLastID])
        #expect(started.first?.readingProgress == 12)
        #expect(model.entries.count > 1)
    }

    /// The list does not follow the progress: a page turn does not rebuild its entries. A page
    /// mapped afterwards reads the progress as it is then.
    @Test func progressIsReadWhenThePageIsMapped() async throws {
        let env = try ListTestEnvironment()
        env.transport.on(.any, reply: .fixture(ListFixture.frontpage))
        let model = env.make { GalleryListModel(source: .frontpage) }
        await model.loadIfNeeded()
        let before = model.entries
        #expect(before.allSatisfy { $0.readingProgress == nil })

        try await env.database.updateReadingProgress(gid: ListFixture.frontpageLastID, progress: 3)
        #expect(model.entries == before)

        await model.refresh()
        #expect(model.entries.first { $0.id == ListFixture.frontpageLastID }?.readingProgress == 3)
    }

    @Test func historyRowsCarryTheirProgress() async throws {
        let env = try ListTestEnvironment()
        try await env.database.recordOpened(.stub("1"), at: Date(timeIntervalSince1970: 10))
        try await env.database.recordOpened(.stub("2"), at: Date(timeIntervalSince1970: 20))
        try await env.database.updateReadingProgress(gid: "1", progress: 7)
        let model = env.make { HistoryModel() }

        await model.refresh()
        #expect(model.entries.map(\.id) == ["2", "1"])
        #expect(model.entries.map(\.readingProgress) == [nil, 7])

        // Opening another gallery sends the rows again, with the progress as it is now; the
        // unchanged entry is reused.
        try await env.database.updateReadingProgress(gid: "2", progress: 4)
        let unchanged = model.entries[1]
        try await env.database.recordOpened(.stub("3"), at: Date(timeIntervalSince1970: 30))
        await model.refresh()
        #expect(model.entries.map(\.readingProgress) == [nil, 4, 7])
        #expect(model.entries[2] == unchanged)
    }

    @Test func copyingProgressKeepsTheParsedTitle() {
        let entry = GalleryEntry(gallery: .stub("1", title: "[Circle (Artist)] Title"), favorite: FavoriteMark(folder: 3))
        let updated = GalleryListPaging.withReadingProgress([entry], ["1": 9])
        #expect(updated.first?.readingProgress == 9)
        #expect(updated.first?.title == entry.title)
        #expect(updated.first?.favorite == entry.favorite)
        #expect(GalleryListPaging.withReadingProgress(updated, ["1": 9]) == updated)
        #expect(GalleryListPaging.withReadingProgress(updated, [:]).first?.readingProgress == nil)
    }
}
