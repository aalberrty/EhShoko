@testable import EhDatabase
import EhModels
import EhTestSupport
import Foundation
import Testing

@Suite struct ReadingListTests {
    /// Opens gallery `gid` (42 pages) at `opened` and records its progress.
    private func open(
        _ gid: String, at opened: Double, progress: Int?, in database: AppDatabase
    ) async throws {
        try await database.recordOpened(SampleData.gallery(gid), at: SampleData.date(opened))
        if let progress {
            try await database.updateReadingProgress(gid: gid, progress: progress)
        }
    }

    private func firstValue(_ database: AppDatabase, limit: Int = 10) async throws -> [ReadingListItem] {
        try await observe(database.observeReadingList(limit: limit), changes: []).first ?? []
    }

    @Test func startedGalleriesMostRecentlyOpenedFirst() async throws {
        let database = try await TestDatabase.inMemory()
        try await open("1", at: 10, progress: 5, in: database)
        try await open("2", at: 30, progress: 41, in: database)
        try await open("3", at: 20, progress: 1, in: database)

        let items = try await firstValue(database)
        #expect(items.map(\.id) == ["2", "3", "1"])
        #expect(items.map(\.page) == [41, 1, 5])
        #expect(items.allSatisfy { $0.pageCount == 42 })
        #expect(items.first?.gallery == SampleData.gallery("2", lastOpenDate: SampleData.date(30)))
    }

    @Test func unreadAndFinishedGalleriesAreLeftOut() async throws {
        let database = try await TestDatabase.inMemory()
        try await open("unread-no-state", at: 1, progress: nil, in: database)
        try await open("unread", at: 2, progress: 0, in: database)
        try await open("finished", at: 3, progress: 42, in: database)
        try await open("past-the-end", at: 4, progress: 50, in: database)
        try await open("started", at: 5, progress: 2, in: database)
        // Progress for a gallery that is not in the history (never opened) is not listed.
        try await database.updateReadingProgress(gid: "not-opened", progress: 3)

        #expect(try await firstValue(database).map(\.id) == ["started"])
    }

    /// The detail's page count is the newest; the list's is used when no detail was fetched.
    @Test func pageCountPrefersTheDetail() async throws {
        let database = try await TestDatabase.inMemory()
        try await open("1", at: 1, progress: 30, in: database)
        try await open("2", at: 2, progress: 20, in: database)
        // `SampleData.detail` has 24 pages: page 30 is past its end, page 20 is not.
        try await database.saveDetail(SampleData.detail("1"), state: GalleryState(gid: "1"))
        try await database.saveDetail(SampleData.detail("2"), state: GalleryState(gid: "2"))

        let items = try await firstValue(database)
        #expect(items.map(\.id) == ["2"])
        #expect(items.first?.pageCount == 24)
    }

    @Test func emitsWhenProgressIsWritten() async throws {
        let database = try await TestDatabase.inMemory()
        try await open("1", at: 1, progress: nil, in: database)

        let values = try await observe(database.observeReadingList(limit: 10), changes: [
            { try await database.updateReadingProgress(gid: "1", progress: 3) },
            { try await database.updateReadingProgress(gid: "1", progress: 4) },
            { try await open("2", at: 2, progress: 7, in: database) },
            // Reading to the last page finishes the gallery.
            { try await database.updateReadingProgress(gid: "1", progress: 42) },
            { try await database.clearHistory() }
        ])
        #expect(values.map { $0.map(\.id) } == [[], ["1"], ["1"], ["2", "1"], ["2"], []])
        #expect(values.map { $0.map(\.page) } == [[], [3], [4], [7, 4], [7], []])
    }

    @Test func aWriteThatChangesNothingDoesNotEmit() async throws {
        let database = try await TestDatabase.inMemory()
        try await open("1", at: 1, progress: 3, in: database)

        let values = try await observe(database.observeReadingList(limit: 10), changes: [
            {
                // An unrelated gallery, not started, leaves the list as it was: the next value
                // is the one after the progress changes.
                try await open("2", at: 2, progress: nil, in: database)
                try await database.updateReadingProgress(gid: "1", progress: 3)
                try await database.updateReadingProgress(gid: "1", progress: 5)
            }
        ])
        #expect(values.map { $0.map(\.page) } == [[3], [5]])
    }

    @Test func theLimit() async throws {
        let database = try await TestDatabase.inMemory()
        for index in 1...5 {
            try await open("\(index)", at: Double(index), progress: index, in: database)
        }
        #expect(try await firstValue(database, limit: 2).map(\.id) == ["5", "4"])
        #expect(try await firstValue(database, limit: 10).count == 5)
    }

    @Test func emptyHistory() async throws {
        let database = try await TestDatabase.inMemory()
        #expect(try await firstValue(database).isEmpty)
    }

    @Test func historyCountFollowsInsertsAndClear() async throws {
        let database = try await TestDatabase.inMemory()
        let values = try await observe(database.observeHistoryCount(), changes: [
            { try await database.recordOpened(SampleData.gallery("1"), at: SampleData.date(1)) },
            { try await database.recordOpened(SampleData.gallery("2"), at: SampleData.date(2)) },
            // Reopening a gallery keeps the count, so the next value is after the next insert.
            {
                try await database.recordOpened(SampleData.gallery("1"), at: SampleData.date(3))
                try await database.recordOpened(SampleData.gallery("3"), at: SampleData.date(4))
            },
            { try await database.clearHistory() }
        ])
        #expect(values == [0, 1, 2, 3, 0])
    }
}
