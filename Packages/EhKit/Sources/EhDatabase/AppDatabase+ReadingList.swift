import EhModels
import Foundation
import GRDB

/// An opened gallery that was read partway: started, not finished.
public struct ReadingListItem: Sendable, Equatable, Identifiable {
    public let gallery: Gallery
    /// The 1-based page last read, between 1 and `pageCount - 1`.
    public let page: Int
    public let pageCount: Int

    public var id: String { gallery.gid }

    public init(gallery: Gallery, page: Int, pageCount: Int) {
        self.gallery = gallery
        self.page = page
        self.pageCount = pageCount
    }
}

// MARK: - Reading list

extension AppDatabase {
    /// Opened galleries with `0 < readingProgress < pageCount`, most recently opened first, at
    /// most `limit` of them. Emits at once, and again whenever a committed change to `gallery`,
    /// `galleryState` or `galleryDetail` changes the result.
    ///
    /// The page count is the detail page's when it was fetched (the newest), else the list's.
    /// A gallery whose last page was shown is finished and is left out.
    public func observeReadingList(limit: Int) -> some AsyncSequence<[ReadingListItem], any Error> & Sendable {
        let observation = ValueObservation.tracking { db in
            try Self.readingList(limit: limit, in: db)
        }
        // Each page turn writes the progress; most writes leave the result as it was.
        .removeDuplicates()
        return observation.values(in: writer, scheduling: .task)
    }

    static func readingList(limit: Int, in db: Database) throws -> [ReadingListItem] {
        try Row.fetchAll(db, sql: readingListSQL, arguments: [limit]).map { row in
            ReadingListItem(
                gallery: try GalleryRecord(row: row).gallery,
                page: row["progress"],
                pageCount: row["totalPages"]
            )
        }
    }

    /// One query: the `lastOpenDate` index gives the order, so reading stops after `limit`
    /// matches, and `galleryState` and `galleryDetail` are looked up by key for each row.
    static let readingListSQL = """
        SELECT g.*, s.readingProgress AS progress,
               coalesce(nullif(d.pageCount, 0), g.pageCount) AS totalPages
        FROM \(Schema.gallery) g
        JOIN \(Schema.galleryState) s ON s.gid = g.gid
        LEFT JOIN \(Schema.galleryDetail) d ON d.gid = g.gid
        WHERE s.readingProgress > 0
          AND s.readingProgress < coalesce(nullif(d.pageCount, 0), g.pageCount)
        ORDER BY g.lastOpenDate DESC
        LIMIT ?
        """
}
