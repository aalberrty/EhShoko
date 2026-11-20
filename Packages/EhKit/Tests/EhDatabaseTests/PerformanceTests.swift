@testable import EhDatabase
import EhModels
import EhTestSupport
import Foundation
import Testing

/// Generous bounds (debug build, tests running in parallel) that still catch quadratic work
/// or per-row statement compilation, which take minutes at these sizes. Measured on the
/// development Mac, debug build, run alone: 60,000 translations ≈ 2.5 s, 2,000 pages ≈ 0.15 s.
@Suite struct PerformanceTests {
    @Test func replacing60000TagTranslationsIsFast() async throws {
        let database = try await TestDatabase.inMemory()
        let namespaces = TagNamespace.allCases
        let translations = (0..<60_000).map { index in
            let namespace = namespaces[index % namespaces.count]
            return StoredTagTranslation(
                key: namespace.rawValue + "tag \(index)",
                translation: TagTranslation(
                    namespace: namespace, key: "tag \(index)", value: "![](https://x.org/\(index).png)值\(index)",
                    description: "description \(index)", linksString: "[link](https://x.org/\(index))"
                ),
                displayValue: "值\(index)",
                valueImageURL: URL(string: "https://x.org/\(index).png")
            )
        }

        // The first replace fills the table so the timed one also deletes 60,000 rows.
        try await database.replaceTagTranslations(translations)
        let clock = ContinuousClock()
        var start = clock.now
        try await database.replaceTagTranslations(translations)
        let elapsed = clock.now - start
        #expect(elapsed < .seconds(120), "\(elapsed)")
        #expect(try await database.tagTranslationCount() == 60_000)

        start = clock.now
        let lookup = try await database.tagTranslationLookup()
        let lookupTime = clock.now - start
        #expect(lookup.count == 60_000)
        #expect(lookupTime < .seconds(60), "\(lookupTime)")
    }

    @Test func upserting2000PagesIsFast() async throws {
        let database = try await TestDatabase.inMemory()
        let pages = (1...2_000).map { index in
            GalleryPage(gid: "1", index: index, pageURL: URL(string: "https://e-hentai.org/s/\(index)"),
                        previewURL: URL(string: "https://ehgt.org/p/\(index).jpg"))
        }
        let images = (1...2_000).map { index in
            GalleryPage(gid: "1", index: index, imageURL: URL(string: "https://x.org/\(index).jpg"),
                        imageWidth: 1280, imageHeight: 1800)
        }

        let clock = ContinuousClock()
        let start = clock.now
        try await database.upsertPages(pages)
        try await database.upsertPages(images)
        let elapsed = clock.now - start
        #expect(elapsed < .seconds(60), "\(elapsed)")
        let stored = try await database.pages(gid: "1")
        #expect(stored.count == 2_000)
        #expect(stored.allSatisfy { $0.pageURL != nil && $0.imageURL != nil && $0.imageWidth == 1280 })
    }

    /// The page translation cache with 10,000 stored pages (200 galleries of 50, eight regions
    /// each): the reader's questions about one gallery and a batch of 50 results are each one
    /// transaction. Measured on the development Mac, debug build, load about 40: the count and
    /// the page list 0.3 to 0.5 ms, one page 1 to 1.6 ms, a batch of 50 about 20 ms.
    @Test func pageTranslationQueriesOn10000Pages() async throws {
        let (database, directory) = try await TestDatabase.onDisk()
        defer { try? FileManager.default.removeItem(at: directory) }
        let modelSet = PageTranslationModelSet.default.key
        func page(gid: Int, index: Int) -> PageTranslation {
            let regions = (0..<8).map { region in
                TranslatedRegion(
                    box: FractionalRect(x: 0.1 * Double(region), y: 0.05, width: 0.083, height: 0.21),
                    balloonBox: FractionalRect(x: 0.1 * Double(region) - 0.01, y: 0.03, width: 0.11, height: 0.26),
                    kind: .dialogue, isVertical: true, score: 0.91,
                    source: "これはテストの台詞です\(region)", translation: "这是测试用的台词\(region)"
                )
            }
            return PageTranslation(
                gid: "\(3_000_000 + gid)", pageIndex: index, modelSetKey: modelSet,
                imageWidth: 1280, imageHeight: 1810, regions: regions, createdAt: Date(timeIntervalSinceReferenceDate: 0)
            )
        }
        try await database.savePageTranslations((0..<200).flatMap { gid in (1...50).map { page(gid: gid, index: $0) } })
        #expect(try await database.rowCount("pageTranslation") == 10_000)

        let clock = ContinuousClock()
        var start = clock.now
        let count = try await database.pageTranslationCount(gid: "3000100", modelSetKey: modelSet)
        let countTime = clock.now - start
        start = clock.now
        let indices = try await database.translatedPageIndices(gid: "3000100", modelSetKey: modelSet)
        let indicesTime = clock.now - start
        start = clock.now
        let one = try await database.pageTranslation(gid: "3000100", pageIndex: 25, modelSetKey: modelSet)
        let readTime = clock.now - start
        let batch = (51...100).map { page(gid: 100, index: $0) }
        var insertTime = Duration.zero
        let commits = try await database.commitCount {
            start = clock.now
            try await database.savePageTranslations(batch)
            insertTime = clock.now - start
        }

        #expect(count == 50 && indices == Array(1...50) && one?.regions.count == 8)
        #expect(commits == 1)
        #expect(try await database.pageTranslationCount(gid: "3000100", modelSetKey: modelSet) == 100)
        // The bound only catches a query that has stopped using the index or a batch that has
        // stopped being one transaction. It is far above the measured times because GitHub's
        // Macs run every suite at once: a 20 ms batch has taken over 3 s there.
        for (name, time) in [("count", countTime), ("indices", indicesTime), ("read", readTime), ("insert", insertTime)] {
            #expect(time < .seconds(30), "\(name): \(time)")
        }
    }
}
