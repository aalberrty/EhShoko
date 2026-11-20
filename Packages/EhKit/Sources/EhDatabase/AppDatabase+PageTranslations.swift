import EhModels
import Foundation
import GRDB

// MARK: - Page translations

extension AppDatabase {
    /// The stored text of one page made with the model set `modelSetKey`, or `nil` when there
    /// is none or its regions no longer decode (the page is then translated again).
    public func pageTranslation(gid: String, pageIndex: Int, modelSetKey: String) async throws -> PageTranslation? {
        try await writer.read { db in
            try Row.fetchOne(
                db,
                sql: """
                SELECT * FROM \(Schema.pageTranslation)
                WHERE gid = ? AND modelSet = ? AND pageIndex = ?
                """,
                arguments: [gid, modelSetKey, pageIndex]
            )
            .flatMap(PageTranslation.init(row:))
        }
    }

    /// How many pages of a gallery have stored text for `modelSetKey`: the mark on the reader's
    /// Translate button. One range of the key's index; no row is read.
    public func pageTranslationCount(gid: String, modelSetKey: String) async throws -> Int {
        try await writer.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM \(Schema.pageTranslation) WHERE gid = ? AND modelSet = ?",
                arguments: [gid, modelSetKey]
            ) ?? 0
        }
    }

    /// The pages of a gallery that have stored text for `modelSetKey`, in order: asked once for
    /// the whole gallery when Translate is pressed, never page by page.
    public func translatedPageIndices(gid: String, modelSetKey: String) async throws -> [Int] {
        try await writer.read { db in
            try Int.fetchAll(
                db,
                sql: """
                SELECT pageIndex FROM \(Schema.pageTranslation)
                WHERE gid = ? AND modelSet = ? ORDER BY pageIndex
                """,
                arguments: [gid, modelSetKey]
            )
        }
    }

    /// Stores `translations` in one transaction, replacing what a page had for the same model
    /// set. The regions are encoded on the database's queue, not the caller's actor.
    public func savePageTranslations(_ translations: [PageTranslation]) async throws {
        guard !translations.isEmpty else { return }
        try await writer.write { db in
            let statement = try db.makeStatement(sql: """
                INSERT OR REPLACE INTO \(Schema.pageTranslation)
                    (gid, pageIndex, modelSet, imageWidth, imageHeight, regions, createdAt)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                """)
            for translation in translations {
                try statement.execute(arguments: [
                    translation.gid, translation.pageIndex, translation.modelSetKey,
                    translation.imageWidth, translation.imageHeight,
                    try JSONColumn.encode(translation.regions), translation.createdAt
                ])
            }
        }
    }

    /// Deletes every stored page of one gallery, for every model set.
    public func deletePageTranslations(gid: String) async throws {
        try await writer.write { db in
            try db.execute(sql: "DELETE FROM \(Schema.pageTranslation) WHERE gid = ?", arguments: [gid])
        }
    }

    /// Deletes every stored page of every gallery, leaving no trace of their text in the
    /// database's files, as Clear History does.
    public func deleteAllPageTranslations() async throws {
        try await deleteLeavingNoTrace([Schema.pageTranslation])
    }

    /// Deletes, in one transaction, the rows of every model set but `modelSetKey`, and the rows
    /// of galleries neither opened nor translated within `interval` before `now`.
    ///
    /// A gallery counts as opened by its `gallery.lastOpenDate`, which the detail page sets.
    /// The reader does not set it, so a gallery read again from Continue would lose its text
    /// while it is being read; a row made within the interval therefore keeps its gallery's
    /// other rows too. Rows of a gallery with no `gallery` row (history cleared) follow the
    /// same rule.
    public func deleteExpiredPageTranslations(
        keepingModelSetKey modelSetKey: String, notOpenedWithin interval: TimeInterval, now: Date = .now
    ) async throws {
        let cutoff = now.addingTimeInterval(-interval)
        try await writer.write { db in
            try db.execute(
                sql: """
                DELETE FROM \(Schema.pageTranslation)
                WHERE modelSet <> :modelSet
                   OR (gid NOT IN (SELECT gid FROM \(Schema.gallery) WHERE lastOpenDate >= :cutoff)
                       AND gid NOT IN (SELECT gid FROM \(Schema.pageTranslation) WHERE createdAt >= :cutoff))
                """,
                arguments: ["modelSet": modelSetKey, "cutoff": cutoff]
            )
        }
    }
}

extension PageTranslation {
    /// A stored row; `nil` when its regions no longer decode.
    init?(row: Row) {
        guard let regions = JSONColumn.decode([TranslatedRegion].self, from: row["regions"]) else { return nil }
        self.init(
            gid: row["gid"],
            pageIndex: row["pageIndex"],
            modelSetKey: row["modelSet"],
            imageWidth: row["imageWidth"],
            imageHeight: row["imageHeight"],
            regions: regions,
            createdAt: row["createdAt"]
        )
    }
}
