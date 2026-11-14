@testable import EhFeatures
import EhModels
import EhParser
import EhTestSupport
import Foundation
import Testing

@Suite struct GalleryEntryTests {
    @Test func theLanguageCodeComesFromTheTagThenTheTitle() {
        let tagged = Gallery.stub("1", title: "[Circle] Title [English]").withTags([
            GalleryTag(rawNamespace: "language", contents: [GalleryTag.Content(
                rawNamespace: "language", text: "chinese", isVotedUp: false, isVotedDown: false, backgroundColor: nil
            )])
        ])
        #expect(GalleryEntry(gallery: tagged).languageCode == "ZH")

        let untagged = Gallery.stub("2", title: "[Circle] Title [英訳]")
        #expect(GalleryEntry(gallery: untagged).languageCode == "EN")

        #expect(GalleryEntry(gallery: .stub("3", title: "[Circle] Title")).languageCode == nil)
        // An unparsed title names no language.
        #expect(GalleryEntry(gallery: .stub("4", title: "Title [English] | Other")).languageCode == nil)
    }

    @Test func entriesAreEqualForEqualGalleries() {
        let gallery = Gallery.stub("1", title: "(C102) [Circle (Artist)] Title")
        #expect(GalleryEntry(gallery: gallery) == GalleryEntry(gallery: gallery))
        #expect(GalleryEntry(gallery: gallery) != GalleryEntry(gallery: gallery, favorite: FavoriteMark(folder: 1)))
        #expect(GalleryEntry(gallery: gallery) != GalleryEntry(gallery: gallery, readingProgress: 3))
        var renamed = gallery
        renamed.title = "(C102) [Circle (Artist)] Title 2"
        #expect(GalleryEntry(gallery: gallery) != GalleryEntry(gallery: renamed))
        #expect(GalleryEntry(gallery: gallery).id == "1")
    }

    @Test func entriesReuseWhatWasParsedForTheSameGallery() {
        let galleries = [Gallery.stub("1", title: "[A] One"), .stub("2", title: "[B] Two")]
        let previous = GalleryEntry.entries(for: galleries)
        var changed = galleries
        changed[1].title = "[B] Two, again"

        let entries = GalleryEntry.entries(
            for: changed, marks: ["1": FavoriteMark(folder: 4)], reusing: previous
        )

        #expect(entries.map(\.title.core) == ["One", "Two, again"])
        #expect(entries[0].favorite == FavoriteMark(folder: 4))
        #expect(entries[1].favorite == nil)
    }

    // MARK: The fixtures' real titles

    /// Every title of every list fixture either parses into parts that all come from the raw
    /// title, or shows as it is.
    @Test func everyFixtureTitleParsesOrShowsAsItIs() throws {
        let titles = try Self.fixtureTitles()
        var parsed = 0
        for title in titles {
            let result = TitleParser.parse(title)
            guard result.isParsed else {
                #expect(result == ParsedTitle(raw: title))
                continue
            }
            parsed += 1
            #expect(!result.core.isEmpty)
            let parts = [result.core, result.event, result.circle, result.parody, result.language, result.translator]
                .compactMap { $0 } + result.artists + result.flags
            for part in parts {
                #expect(title.contains(part), "\(part) is not in \(title)")
            }
        }
        // Most real titles follow the convention.
        #expect(titles.count > 400)
        #expect(parsed * 10 >= titles.count * 6, "\(parsed) of \(titles.count) parsed")
    }

    // MARK: Cost

    /// A page of entries and 1,000 titles cost little enough to build when a page arrives.
    /// Both run off the main actor in the app; the best of several runs is timed, so a busy
    /// machine does not fail the test.
    @Test func buildingEntriesIsCheap() async throws {
        let galleries = try Self.fixtureGalleries()
        let page = Array(galleries.prefix(100))
        let titles = Array((0..<1000).map { galleries[$0 % galleries.count].title })
        #expect(page.count == 100)

        let (pageTime, titlesTime) = await Self.measure(page: page, titles: titles)

        #expect(pageTime < .milliseconds(20), "100 entries took \(pageTime)")
        #expect(titlesTime < .milliseconds(200), "1,000 titles took \(titlesTime)")
    }

    @concurrent
    nonisolated private static func measure(page: [Gallery], titles: [String]) async -> (Duration, Duration) {
        let clock = ContinuousClock()
        var pageTime = Duration.seconds(60)
        var titlesTime = Duration.seconds(60)
        for _ in 0..<5 {
            pageTime = min(pageTime, clock.measure { _ = GalleryEntry.entries(for: page) })
            titlesTime = min(titlesTime, clock.measure { for title in titles { _ = TitleParser.parse(title) } })
        }
        return (pageTime, titlesTime)
    }

    // MARK: Helpers

    nonisolated static let listFixtures = [
        "Favorites", "FrontPage", "Popular", "Watched"
    ].flatMap { list in
        ["Compact", "Extended", "Minimal", "MinimalPlus", "Thumbnail"].map { "Parser/List/\(list)\($0)List.html" }
    } + ["Parser/List/ToplistsCompactList.html"]

    nonisolated static func fixtureGalleries() throws -> [Gallery] {
        try listFixtures.flatMap { path in
            try Parser.parseGalleries(doc: Parser.htmlDocument(data: Fixture.data(path)))
        }
    }

    nonisolated static func fixtureTitles() throws -> [String] {
        var seen = Set<String>()
        return try fixtureGalleries().map(\.title).filter { seen.insert($0).inserted }
    }
}

private extension Gallery {
    func withTags(_ tags: [GalleryTag]) -> Gallery {
        var gallery = self
        gallery.tags = tags
        return gallery
    }
}
