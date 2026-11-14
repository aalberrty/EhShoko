@testable import EhDatabase
import EhModels
import EhTestSupport
import Foundation
import GRDB
import Testing

@Suite struct ReadingProgressTests {
    @Test func startedGalleriesOfThePageOnly() async throws {
        let database = try await TestDatabase.inMemory()
        try await database.updateReadingProgress(gid: "1", progress: 5)
        try await database.updateReadingProgress(gid: "2", progress: 0)
        try await database.updateReadingProgress(gid: "3", progress: 42)
        try await database.updateReadingProgress(gid: "not-asked", progress: 7)
        // A state row without progress (a detail fetched, never read).
        try await database.saveDetail(SampleData.detail("4"), state: GalleryState(gid: "4"))

        let progress = try await database.readingProgress(gids: ["1", "2", "3", "4", "never-seen"])
        #expect(progress == ["1": 5, "3": 42])
    }

    @Test func noGalleriesNoQuery() async throws {
        let database = try await TestDatabase.inMemory()
        #expect(try await database.readingProgress(gids: []).isEmpty)
    }

    /// More galleries than one statement binds are read in chunks of the same read.
    @Test func longListsAreReadInChunks() async throws {
        let database = try await TestDatabase.inMemory()
        let count = AppDatabase.readingProgressChunk * 2 + 7
        try await database.writer.write { db in
            for index in 0..<count {
                try db.execute(
                    sql: "INSERT INTO \(Schema.galleryState) (gid, readingProgress) VALUES (?, ?)",
                    arguments: ["\(index)", index + 1]
                )
            }
        }
        let progress = try await database.readingProgress(gids: (0..<count).map { "\($0)" })
        #expect(progress.count == count)
        #expect(progress["0"] == 1)
        #expect(progress["\(count - 1)"] == count)
    }

    @Test func observingOneGalleryFollowsItsProgressOnly() async throws {
        let database = try await TestDatabase.inMemory()
        let values = try await observe(database.observeReadingProgress(gid: "1"), changes: [
            { try await database.updateReadingProgress(gid: "1", progress: 3) },
            {
                // Neither another gallery's progress nor the rest of the row is sent.
                try await database.updateReadingProgress(gid: "2", progress: 9)
                try await database.saveDetail(SampleData.detail("1"), state: GalleryState(gid: "1"))
                try await database.updateReadingProgress(gid: "1", progress: 3)
                try await database.updateReadingProgress(gid: "1", progress: 4)
            },
            { try await database.clearHistory() }
        ])
        #expect(values == [0, 3, 4, 0])
    }
}
