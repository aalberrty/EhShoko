import EhModels
import Foundation
import GRDB

// MARK: - Reading progress

extension AppDatabase {
    /// The stored reading progress of each of `gids` that was started (progress above 0), in
    /// one read: what a page of list rows shows. Galleries never read are absent.
    ///
    /// The rows are looked up by primary key, so the cost follows the number of `gids`, not the
    /// size of the history.
    public func readingProgress(gids: [String]) async throws -> [String: Int] {
        guard !gids.isEmpty else { return [:] }
        return try await writer.read { db in
            try Self.readingProgress(gids: gids, in: db)
        }
    }

    /// SQLite limits the number of bound values in one statement (32,766 in the versions GRDB
    /// ships, 999 in old ones), so a long list is read in chunks, inside the same read.
    static let readingProgressChunk = 500

    static func readingProgress(gids: [String], in db: Database) throws -> [String: Int] {
        var progress = [String: Int]()
        var start = gids.startIndex
        while start < gids.endIndex {
            let end = min(start + readingProgressChunk, gids.endIndex)
            let chunk = Array(gids[start..<end])
            let rows = try Row.fetchCursor(
                db, sql: readingProgressSQL(count: chunk.count), arguments: StatementArguments(chunk)
            )
            while let row = try rows.next() {
                progress[row["gid"]] = row["readingProgress"]
            }
            start = end
        }
        return progress
    }

    static func readingProgressSQL(count: Int) -> String {
        let placeholders = Array(repeating: "?", count: count).joined(separator: ",")
        return """
            SELECT gid, readingProgress FROM \(Schema.galleryState)
            WHERE gid IN (\(placeholders)) AND readingProgress > 0
            """
    }

    /// The stored reading progress of one gallery (0 when it was never read). Emits at once and
    /// again whenever the progress changes; other writes to the row are not sent. The reader
    /// writes it once it has rested on a page, not on every page turn.
    public func observeReadingProgress(gid: String) -> some AsyncSequence<Int, any Error> & Sendable {
        let observation = ValueObservation.tracking { db in
            try Int.fetchOne(
                db, sql: "SELECT readingProgress FROM \(Schema.galleryState) WHERE gid = ?", arguments: [gid]
            ) ?? 0
        }
        .removeDuplicates()
        return observation.values(in: writer, scheduling: .task)
    }
}
