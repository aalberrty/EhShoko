@testable import EhDatabase
import EhModels
import EhTestSupport
import Foundation
import Testing

@Suite struct HistoryTests {
    @Test func recordOpenedStoresGalleryWithOpenDate() async throws {
        let database = try await TestDatabase.inMemory()
        let gallery = SampleData.gallery("100")
        try await database.recordOpened(gallery, at: SampleData.date(1000))

        let stored = try #require(try await database.gallery(gid: "100"))
        #expect(stored.gid == "100")
        #expect(stored.token == gallery.token)
        #expect(stored.title == gallery.title)
        #expect(stored.rating == gallery.rating)
        #expect(stored.tags == gallery.tags)
        #expect(stored.category == gallery.category)
        #expect(stored.uploader == gallery.uploader)
        #expect(stored.pageCount == gallery.pageCount)
        #expect(stored.postedDate == gallery.postedDate)
        #expect(stored.coverURL == gallery.coverURL)
        #expect(stored.galleryURL == gallery.galleryURL)
        #expect(stored.lastOpenDate == SampleData.date(1000))
        #expect(try await database.gallery(gid: "missing") == nil)
    }

    @Test func recordOpenedAgainUpdatesRowAndDate() async throws {
        let database = try await TestDatabase.inMemory()
        try await database.recordOpened(SampleData.gallery("1", title: "Old"), at: SampleData.date(1))
        try await database.recordOpened(SampleData.gallery("1", title: "New"), at: SampleData.date(2))
        let stored = try #require(try await database.gallery(gid: "1"))
        #expect(stored.title == "New")
        #expect(stored.lastOpenDate == SampleData.date(2))
        #expect(try await database.rowCount("gallery") == 1)
    }

    @Test func millisecondDatesRoundTrip() async throws {
        let database = try await TestDatabase.inMemory()
        let date = SampleData.date(123.456)
        try await database.recordOpened(SampleData.gallery("1"), at: date)
        let stored = try #require(try await database.gallery(gid: "1")?.lastOpenDate)
        #expect(abs(stored.timeIntervalSince(date)) < 0.001)
    }

    @Test func historyIsNewestFirstWithLimit() async throws {
        let database = try await TestDatabase.inMemory()
        try await database.recordOpened(SampleData.gallery("1"), at: SampleData.date(10))
        try await database.recordOpened(SampleData.gallery("2"), at: SampleData.date(30))
        try await database.recordOpened(SampleData.gallery("3"), at: SampleData.date(20))

        let all = try await observe(database.observeHistory(), changes: [])
        #expect(all.first?.map(\.gid) == ["2", "3", "1"])
        let limited = try await observe(database.observeHistory(limit: 2), changes: [])
        #expect(limited.first?.map(\.gid) == ["2", "3"])
    }

    @Test func historyObservationEmitsOnChange() async throws {
        let database = try await TestDatabase.inMemory()
        let values = try await observe(database.observeHistory(), changes: [
            { try await database.recordOpened(SampleData.gallery("1"), at: SampleData.date(1)) },
            { try await database.recordOpened(SampleData.gallery("2"), at: SampleData.date(2)) },
            { try await database.clearHistory() }
        ])
        #expect(values.map { $0.map(\.gid) } == [[], ["1"], ["2", "1"], []])
    }

    @Test func historyPagesAreLimitedAndSayWhetherMoreFollow() async throws {
        let database = try await TestDatabase.inMemory()
        for index in 1...5 {
            try await database.recordOpened(SampleData.gallery("\(index)"), at: SampleData.date(Double(index)))
        }

        let first = try await observe(database.observeHistory(limit: 2, titleFilter: ""), changes: [])
        #expect(first.first?.hasMore == true)
        #expect(first.first?.isHistoryEmpty == false)
        #expect(first.first?.galleries.map(\.gid) == ["5", "4"])
        let all = try await observe(database.observeHistory(limit: 5, titleFilter: ""), changes: [])
        #expect(all.first?.galleries.map(\.gid) == ["5", "4", "3", "2", "1"])
        #expect(all.first?.hasMore == false)
    }

    /// The filter searches the whole history, not only the rows of the first page.
    @Test func historyTitleFilterSearchesEveryRowIgnoringCase() async throws {
        let database = try await TestDatabase.inMemory()
        try await database.recordOpened(SampleData.gallery("1", title: "Old Ünïcode Title"), at: SampleData.date(1))
        for index in 2...10 {
            try await database.recordOpened(SampleData.gallery("\(index)", title: "Other"), at: SampleData.date(Double(index)))
        }

        let values = try await observe(database.observeHistory(limit: 2, titleFilter: "ünÏCODE"), changes: [])
        #expect(values.first?.galleries.map(\.gid) == ["1"])
        #expect(values.first?.hasMore == false)
        #expect(values.first?.isHistoryEmpty == false)
        let none = try await observe(database.observeHistory(limit: 2, titleFilter: "missing"), changes: [])
        #expect(none.first?.galleries.isEmpty == true)
        #expect(none.first?.isHistoryEmpty == false)
    }

    @Test func historyPageObservationEmitsOnChange() async throws {
        let database = try await TestDatabase.inMemory()
        let values = try await observe(database.observeHistory(limit: 1, titleFilter: ""), changes: [
            { try await database.recordOpened(SampleData.gallery("1"), at: SampleData.date(1)) },
            { try await database.recordOpened(SampleData.gallery("2"), at: SampleData.date(2)) },
            { try await database.clearHistory() }
        ])
        #expect(values.map { $0.galleries.map(\.gid) } == [[], ["1"], ["2"], []])
        #expect(values.map(\.hasMore) == [false, false, true, false])
        #expect(values.map(\.isHistoryEmpty) == [true, false, false, true])
    }

    @Test func clearHistoryDeletesAllGalleryData() async throws {
        let database = try await TestDatabase.inMemory()
        try await database.recordOpened(SampleData.gallery("1"))
        try await database.saveDetail(SampleData.detail("1"), state: GalleryState(gid: "1"))
        try await database.updateReadingProgress(gid: "1", progress: 5)
        try await database.upsertPages([GalleryPage(gid: "1", index: 1, imageURL: SampleData.url("1.jpg"))])
        // The translated text of the pages read goes with them.
        try await database.savePageTranslations([
            PageTranslationTests.page(gid: "1", index: 1), PageTranslationTests.page(gid: "3", index: 2)
        ])
        // Rows for a gallery without a `gallery` row are cleared too.
        try await database.saveDetail(SampleData.detail("2"), state: GalleryState(gid: "2"))
        try await database.recordSearchKeyword("kept")

        let commits = try await database.commitCount {
            try await database.clearHistory()
        }

        // One transaction deletes it all (the checkpoint after it commits nothing).
        #expect(commits == 1)
        for table in ["gallery", "galleryDetail", "galleryState", "galleryPage", "pageTranslation"] {
            #expect(try await database.rowCount(table) == 0, "\(table)")
        }
        #expect(try await database.gallery(gid: "1") == nil)
        #expect(try await database.detail(gid: "1") == nil)
        #expect(try await database.state(gid: "1") == nil)
        #expect(try await database.pages(gid: "1").isEmpty)
        // Search history is a separate list with its own clear action.
        #expect(try await database.rowCount("searchHistory") == 1)
    }

    @Test func clearHistoryOnDiskLeavesDatabaseUsable() async throws {
        let (database, directory) = try await TestDatabase.onDisk()
        defer { try? FileManager.default.removeItem(at: directory) }
        try await database.recordOpened(SampleData.gallery("1"))
        try await database.clearHistory()
        #expect(try await database.rowCount("gallery") == 0)
        try await database.recordOpened(SampleData.gallery("2"))
        #expect(try await database.rowCount("gallery") == 1)
    }

    @Test func clearHistoryLeavesNoTraceInTheDatabaseFiles() async throws {
        let (database, directory) = try await TestDatabase.onDisk()
        defer { try? FileManager.default.removeItem(at: directory) }
        let marker = "UNIQUE-TITLE-MARKER-7F3A"
        let textMarker = "UNIQUE-PAGE-TEXT-MARKER-91C2"
        for index in 0..<20 {
            try await database.recordOpened(SampleData.gallery("\(index)", title: "\(marker) \(index)"))
        }
        // Translated text, in rows of a page each; the last is longer than a database page, so
        // its text also sits in overflow pages.
        try await database.savePageTranslations((0..<20).map { index in
            PageTranslationTests.page(gid: "\(index)", index: 1, translation: "\(textMarker) \(index)")
        } + [PageTranslationTests.page(
            gid: "0", index: 2, translation: String(repeating: "\(textMarker) ", count: 600)
        )])
        // The text is on disk before the clear, so finding none after it means something.
        #expect(try Self.filesHold(textMarker, in: directory))

        try await database.clearHistory()

        // The deleted rows must be gone from the main file and from the write-ahead log.
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        #expect(!files.isEmpty)
        for file in files {
            let data = try Data(contentsOf: file)
            #expect(data.range(of: Data(marker.utf8)) == nil, "\(file.lastPathComponent) still holds a cleared title")
            #expect(
                data.range(of: Data(textMarker.utf8)) == nil,
                "\(file.lastPathComponent) still holds a cleared page's text"
            )
        }
    }

    /// Whether any of the database's files in `directory` holds `marker`.
    static func filesHold(_ marker: String, in directory: URL) throws -> Bool {
        try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).contains { file in
            try Data(contentsOf: file).range(of: Data(marker.utf8)) != nil
        }
    }
}
