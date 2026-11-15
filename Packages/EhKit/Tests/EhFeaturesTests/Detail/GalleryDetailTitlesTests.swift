import EhDatabase
import EhFeatures
import EhModels
import EhTestSupport
import Foundation
import Testing

@Suite struct GalleryTitlesTests {
    private static let english = "(C103) [Circle (Artist)] The Title (Parody) [English]"
    private static let japanese = "(C103) [サークル (作家)] 題名 (パロディ) [英訳]"

    @Test func parsesBothTitles() {
        let titles = GalleryTitles(title: Self.english, japaneseTitle: Self.japanese)
        #expect(titles.parsedTitle == TitleParser.parse(Self.english))
        #expect(titles.parsedTitle.core == "The Title")
        #expect(titles.parsedJapaneseTitle == TitleParser.parse(Self.japanese))
        #expect(titles.parsedJapaneseTitle?.core == "題名")
    }

    @Test func anEmptyJapaneseTitleIsNone() {
        let titles = GalleryTitles(title: Self.english, japaneseTitle: "")
        #expect(titles.japaneseTitle == nil)
        #expect(titles.parsedJapaneseTitle == nil)
        #expect(titles.shown(prefersJapanese: true).full == Self.english)
    }

    @Test func showsThePreferredTitleWithTheOtherBeneath() {
        let titles = GalleryTitles(title: Self.english, japaneseTitle: Self.japanese)

        let english = titles.shown(prefersJapanese: false)
        #expect(english.full == Self.english)
        #expect(english.parsed.core == "The Title")
        #expect(english.other == Self.japanese)

        let japanese = titles.shown(prefersJapanese: true)
        #expect(japanese.full == Self.japanese)
        #expect(japanese.parsed.core == "題名")
        #expect(japanese.other == Self.english)
    }

    /// Without another title, the shown one is written in full when parsing shortened it, and
    /// not at all when the parsed title is all of it.
    @Test func theOtherTitleNeverRepeatsWhatIsShown() {
        #expect(GalleryTitles(title: Self.english).shown(prefersJapanese: true).other == Self.english)
        #expect(GalleryTitles(title: "Plain title").shown(prefersJapanese: false).other == nil)
        // The same string twice is one title.
        let twice = GalleryTitles(title: "Plain title", japaneseTitle: "Plain title")
        #expect(twice.shown(prefersJapanese: true).other == nil)
    }

    @Test func titlesAreEqualForEqualStrings() {
        #expect(GalleryTitles(title: "A", japaneseTitle: "B") == GalleryTitles(title: "A", japaneseTitle: "B"))
        #expect(GalleryTitles(title: "A", japaneseTitle: "B") != GalleryTitles(title: "A", japaneseTitle: nil))
        #expect(GalleryTitles(title: "A") != GalleryTitles(title: "B"))
    }
}

/// The model's parsed titles: the list's in the first frame, then the page's.
@MainActor
@Suite struct GalleryDetailTitlesTests {
    @Test func theListTitleIsParsedBeforeAnythingLoads() async throws {
        let env = try await DetailEnvironment()
        var gallery = DetailEnvironment.gallery
        gallery.title = "(C103) [Circle (Artist)] The Title (Parody) [English]"
        let model = env.makeDetailModel(gallery: gallery)
        #expect(model.titles.title == gallery.title)
        #expect(model.titles.parsedTitle.core == "The Title")
        #expect(model.titles.parsedTitle.circle == "Circle")
        #expect(model.titles.japaneseTitle == nil)
        #expect(env.transport.requests.isEmpty)
    }

    @Test func theFetchedPageBringsItsTitlesParsed() async throws {
        let env = try await DetailEnvironment()
        let model = await env.loadedDetailModel()
        #expect(model.titles.title == "[Artist] mks")
        #expect(model.titles.parsedTitle == TitleParser.parse("[Artist] mks"))
        #expect(model.titles.japaneseTitle == "[アーティスト] mks")
        #expect(model.titles.parsedJapaneseTitle == TitleParser.parse("[アーティスト] mks"))
        // Applied with the page: whoever sees the page's title sees it parsed.
        #expect(model.titles.title == model.detail?.title)
    }

    @Test func theStoredPageBringsItsTitlesBeforeTheFetch() async throws {
        let env = try await DetailEnvironment()
        let stored = GalleryDetail(
            gid: DetailEnvironment.gid, title: "[Stored Circle] Stored title", jpnTitle: "保存された題名",
            isFavorited: false, visibility: .yes, rating: 3, userRating: 0, ratingCount: 1, category: .nonH,
            language: .japanese, uploader: "Stored uploader", postedDate: .now, coverURL: nil, favoritedCount: 1,
            pageCount: 156, sizeCount: 1, sizeType: "MiB", torrentCount: 0
        )
        try await env.database.saveDetail(stored, state: GalleryState(gid: DetailEnvironment.gid))

        let (gate, release) = AsyncStream<Void>.makeStream()
        env.transport.on(.path(DetailEnvironment.detailPath), reply: .handler { request in
            for await _ in gate { break }
            return try fixtureResponse("Parser/Gallery/GalleryDetail.html", for: request)
        })
        let model = env.makeDetailModel()
        let loading = Task { await model.load() }

        await pollUntil { model.detail?.title == "[Stored Circle] Stored title" }
        #expect(model.titles.title == "[Stored Circle] Stored title")
        #expect(model.titles.parsedTitle.core == "Stored title")
        #expect(model.titles.japaneseTitle == "保存された題名")

        release.yield()
        await loading.value
        #expect(model.titles.title == "[Artist] mks")
    }
}
