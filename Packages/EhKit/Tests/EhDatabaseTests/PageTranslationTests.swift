@testable import EhDatabase
import EhModels
import EhTestSupport
import Foundation
import Testing

@Suite struct PageTranslationTests {
    static let modelSet = PageTranslationModelSet.default.key
    static let otherModelSet = PageTranslationModelSet(translator: .hyMT2).key

    @Test func migrationCreatesTheTable() async throws {
        let database = try await TestDatabase.inMemory()
        let columns = try await database.schemaColumns()
        #expect(columns["pageTranslation"] == [
            "gid", "pageIndex", "modelSet", "imageWidth", "imageHeight", "regions", "createdAt"
        ])
        #expect(try await database.indexNames().contains("pageTranslation_on_gid_modelSet_pageIndex"))
    }

    @Test func storesAndReadsAPage() async throws {
        let database = try await TestDatabase.inMemory()
        let page = Self.page(gid: "1", index: 3)
        try await database.savePageTranslations([page, Self.page(gid: "1", index: 4)])

        #expect(try await database.pageTranslation(gid: "1", pageIndex: 3, modelSetKey: Self.modelSet) == page)
        #expect(try await database.pageTranslation(gid: "1", pageIndex: 5, modelSetKey: Self.modelSet) == nil)
        #expect(try await database.pageTranslation(gid: "2", pageIndex: 3, modelSetKey: Self.modelSet) == nil)
        // Another detector, reader or translator never sees this result.
        #expect(try await database.pageTranslation(gid: "1", pageIndex: 3, modelSetKey: Self.otherModelSet) == nil)
    }

    @Test func aPageWithoutRegionsIsStored() async throws {
        let database = try await TestDatabase.inMemory()
        let empty = Self.page(gid: "1", index: 1, regions: [])
        try await database.savePageTranslations([empty])
        #expect(try await database.pageTranslation(gid: "1", pageIndex: 1, modelSetKey: Self.modelSet) == empty)
    }

    @Test func savingAgainReplacesThePage() async throws {
        let database = try await TestDatabase.inMemory()
        try await database.savePageTranslations([Self.page(gid: "1", index: 1)])
        let newer = Self.page(gid: "1", index: 1, translation: "新的", createdAt: SampleData.date(2_000))
        try await database.savePageTranslations([newer])
        #expect(try await database.pageTranslation(gid: "1", pageIndex: 1, modelSetKey: Self.modelSet) == newer)
        #expect(try await database.rowCount("pageTranslation") == 1)
    }

    @Test func countsAndListsAGallerysPagesForOneModelSet() async throws {
        let database = try await TestDatabase.inMemory()
        try await database.savePageTranslations([
            Self.page(gid: "1", index: 7), Self.page(gid: "1", index: 2), Self.page(gid: "1", index: 10),
            Self.page(gid: "1", index: 4, modelSet: Self.otherModelSet),
            Self.page(gid: "11", index: 1), Self.page(gid: "2", index: 1)
        ])
        #expect(try await database.pageTranslationCount(gid: "1", modelSetKey: Self.modelSet) == 3)
        #expect(try await database.translatedPageIndices(gid: "1", modelSetKey: Self.modelSet) == [2, 7, 10])
        #expect(try await database.pageTranslationCount(gid: "1", modelSetKey: Self.otherModelSet) == 1)
        #expect(try await database.pageTranslationCount(gid: "3", modelSetKey: Self.modelSet) == 0)
        #expect(try await database.translatedPageIndices(gid: "3", modelSetKey: Self.modelSet).isEmpty)
    }

    @Test func aBatchIsOneTransaction() async throws {
        let database = try await TestDatabase.inMemory()
        let pages = (1...50).map { Self.page(gid: "1", index: $0) }
        let commits = try await database.commitCount {
            try await database.savePageTranslations(pages)
        }
        #expect(commits == 1)
        #expect(try await database.pageTranslationCount(gid: "1", modelSetKey: Self.modelSet) == 50)
    }

    @Test func anEmptyBatchWritesNothing() async throws {
        let database = try await TestDatabase.inMemory()
        let commits = try await database.commitCount {
            try await database.savePageTranslations([])
        }
        #expect(commits == 0)
    }

    @Test func aRowWhoseRegionsNoLongerDecodeIsNotFound() async throws {
        let database = try await TestDatabase.inMemory()
        try await database.savePageTranslations([Self.page(gid: "1", index: 1)])
        try await database.writer.write { db in
            try db.execute(sql: "UPDATE pageTranslation SET regions = '[{\"box\":1}]'")
        }
        #expect(try await database.pageTranslation(gid: "1", pageIndex: 1, modelSetKey: Self.modelSet) == nil)
    }

    @Test func deletesOneGalleryOrAll() async throws {
        let database = try await TestDatabase.inMemory()
        try await database.savePageTranslations([
            Self.page(gid: "1", index: 1), Self.page(gid: "1", index: 2, modelSet: Self.otherModelSet),
            Self.page(gid: "2", index: 1)
        ])
        try await database.deletePageTranslations(gid: "1")
        #expect(try await database.pageTranslationCount(gid: "1", modelSetKey: Self.modelSet) == 0)
        #expect(try await database.pageTranslationCount(gid: "1", modelSetKey: Self.otherModelSet) == 0)
        #expect(try await database.pageTranslationCount(gid: "2", modelSetKey: Self.modelSet) == 1)

        try await database.deleteAllPageTranslations()
        #expect(try await database.rowCount("pageTranslation") == 0)
    }

    @Test func expiryKeepsOnlyTheCurrentModelSetOfGalleriesOpenedOrTranslatedLately() async throws {
        let database = try await TestDatabase.inMemory()
        let now = SampleData.date(100 * Self.day)
        let longAgo = SampleData.date(50 * Self.day), lately = SampleData.date(90 * Self.day)
        // 1: opened lately. 2: opened long ago, translated long ago. 3: opened long ago, a page
        // translated lately (read again from Continue). 4: never recorded as opened (history
        // cleared), translated long ago.
        try await database.recordOpened(SampleData.gallery("1"), at: lately)
        try await database.recordOpened(SampleData.gallery("2"), at: longAgo)
        try await database.recordOpened(SampleData.gallery("3"), at: longAgo)
        try await database.savePageTranslations([
            Self.page(gid: "1", index: 1, createdAt: longAgo),
            Self.page(gid: "1", index: 2, modelSet: Self.otherModelSet, createdAt: lately),
            Self.page(gid: "2", index: 1, createdAt: longAgo),
            Self.page(gid: "3", index: 1, createdAt: longAgo),
            Self.page(gid: "3", index: 2, createdAt: lately),
            Self.page(gid: "4", index: 1, createdAt: longAgo)
        ])

        let commits = try await database.commitCount {
            try await database.deleteExpiredPageTranslations(
                keepingModelSetKey: Self.modelSet, notOpenedWithin: 30 * Self.day, now: now
            )
        }
        #expect(commits == 1)
        #expect(try await database.translatedPageIndices(gid: "1", modelSetKey: Self.modelSet) == [1])
        #expect(try await database.pageTranslationCount(gid: "1", modelSetKey: Self.otherModelSet) == 0)
        #expect(try await database.pageTranslationCount(gid: "2", modelSetKey: Self.modelSet) == 0)
        #expect(try await database.translatedPageIndices(gid: "3", modelSetKey: Self.modelSet) == [1, 2])
        #expect(try await database.pageTranslationCount(gid: "4", modelSetKey: Self.modelSet) == 0)
    }

    static let day: Double = 24 * 60 * 60

    static func page(
        gid: String, index: Int, modelSet: String = modelSet, translation: String = "你好",
        createdAt: Date = SampleData.date(1_000)
    ) -> PageTranslation {
        page(gid: gid, index: index, modelSet: modelSet, regions: [
            TranslatedRegion(
                box: FractionalRect(x: 0.1, y: 0.2, width: 0.25, height: 0.125),
                balloonBox: FractionalRect(x: 0.05, y: 0.15, width: 0.375, height: 0.25),
                kind: .dialogue, isVertical: true, score: 0.875, source: "こんにちは", translation: translation
            ),
            TranslatedRegion(
                box: FractionalRect(x: 0.5, y: 0.5, width: 0.125, height: 0.0625),
                kind: .soundEffect, isVertical: false, score: 0.5
            )
        ], createdAt: createdAt)
    }

    static func page(
        gid: String, index: Int, modelSet: String = modelSet, regions: [TranslatedRegion],
        createdAt: Date = SampleData.date(1_000)
    ) -> PageTranslation {
        PageTranslation(
            gid: gid, pageIndex: index, modelSetKey: modelSet, imageWidth: 1280, imageHeight: 1810,
            regions: regions, createdAt: createdAt
        )
    }
}
