@testable import EhFeatures
import EhModels
import EhTestSupport
import Foundation
import Testing

/// What a list publishes for the list designs: entries with parsed titles and favourite marks,
/// the favourites folders, and where each page of a numbered list starts.
@Suite struct GalleryListEntriesTests {
    @Test func entriesCarryParsedTitlesAndLanguageCodes() async throws {
        let env = try ListTestEnvironment()
        env.transport.on(.any, reply: .fixture(ListFixture.frontpage))
        let model = env.make { GalleryListModel(source: .frontpage) }

        await model.loadIfNeeded()

        let entry = try #require(model.entries.first { $0.gallery.title == "[ROM宅 (ROM)] せめぱん3 (ドラゴンボールGT) [DL版]" })
        #expect(entry.title.core == "せめぱん3")
        #expect(entry.title.circle == "ROM宅")
        #expect(entry.title.artists == ["ROM"])
        #expect(entry.title.parody == "ドラゴンボールGT")
        #expect(entry.title.flags == ["DL版"])
        for entry in model.entries {
            #expect(entry.title == TitleParser.parse(entry.gallery.title))
            #expect(entry.languageCode == GalleryEntry.languageCode(of: entry.gallery, title: entry.title))
        }
        #expect(model.visibleEntries == model.entries)
    }

    @Test func entriesCarryTheFavouriteMarksOfTheirPage() async throws {
        let env = try ListTestEnvironment()
        let html = try Fixture.string(ListFixture.frontpage).replacingOccurrences(
            of: #"id="posted_2668616""#, with: #"style="border-color:#f00" id="posted_2668616""#
        )
        env.transport.on(.any, reply: .html(html))

        for source in [GalleryListSource.frontpage, .popular, .search(keyword: "x")] {
            let model = env.make { GalleryListModel(source: source) }
            await model.loadIfNeeded()
            #expect(model.entries.first { $0.id == "2668616" }?.favorite == FavoriteMark(folder: 1))
            #expect(model.entries.filter { $0.favorite != nil }.count == 1)
        }
        // Popular asked for its page once, like the other lists.
        #expect(env.transport.requests.count == 3)
    }

    @Test func aFavouritesPageMarksItsEntriesAndUpdatesTheFolders() async throws {
        let env = try ListTestEnvironment()
        env.transport.on(.any, reply: .fixture("Parser/List/FavoritesMinimalList.html"))
        let model = env.make { GalleryListModel(source: .favorites(category: 2, keyword: "", sortOrder: nil)) }
        #expect(env.userStore.favoriteFolderCounts.isEmpty)

        await model.loadIfNeeded()

        #expect(!model.entries.isEmpty)
        #expect(model.entries.allSatisfy { $0.favorite != nil })
        let entry = try #require(model.entries.first { $0.id == "1991004" })
        #expect(entry.favorite?.folder == 2)
        #expect(entry.favorite?.favoritedDate != nil)
        #expect(env.userStore.favoriteFolderCounts.count == 10)
        #expect(env.userStore.favoriteFolderCounts[0] == 117)
        #expect(env.userStore.user.favoriteCategories?[0] == "Favorites 0")
    }

    @Test func otherListsLeaveTheFoldersAlone() async throws {
        let env = try ListTestEnvironment()
        env.transport.on(.any, reply: .fixture(ListFixture.frontpage))
        await env.make { GalleryListModel(source: .frontpage) }.loadIfNeeded()
        #expect(env.userStore.favoriteFolderCounts.isEmpty)
    }

    // MARK: Page starts

    @Test func numberedListsPublishWhereEachPageStarts() async throws {
        let env = try ListTestEnvironment()
        try serveToplists(on: env)
        let model = env.make { GalleryListModel(source: .toplists(.yesterday)) }

        await model.loadIfNeeded()
        let perPage = model.entries.count
        #expect(perPage > 0)
        #expect(model.pageStarts == [PageStart(page: 1, index: 0)])

        await model.loadMore()
        await model.loadMore()

        #expect(model.pageStarts == [
            PageStart(page: 1, index: 0), PageStart(page: 2, index: perPage), PageStart(page: 3, index: 2 * perPage)
        ])
        #expect(model.entries.count == 3 * perPage)
    }

    @Test func aJumpStartsThePageStartsAgain() async throws {
        let env = try ListTestEnvironment()
        try serveToplists(on: env)
        let model = env.make { GalleryListModel(source: .toplists(.yesterday)) }
        await model.loadIfNeeded()
        await model.loadMore()

        #expect(model.jumpToPage("5"))
        #expect(model.pageStarts.isEmpty)
        await model.loadIfNeeded()
        let perPage = model.entries.count
        await model.loadMore()

        #expect(model.pageStarts == [PageStart(page: 5, index: 0), PageStart(page: 6, index: perPage)])
    }

    @Test func aPageOfOnlyKnownGalleriesAddsNoStart() async throws {
        let env = try ListTestEnvironment()
        env.transport.on(.any, reply: .fixture(ListFixture.toplists))
        env.transport.on(.query("p", "1"), reply: try Self.toplistsPage(2, gidPrefix: ""))
        let model = env.make { GalleryListModel(source: .toplists(.yesterday)) }
        await model.loadIfNeeded()

        await model.loadMore()

        #expect(model.pageStarts == [PageStart(page: 1, index: 0)])
    }

    @Test func cursorListsPublishNoPageStarts() async throws {
        let env = try ListTestEnvironment()
        env.transport.on(.any, reply: .fixture(ListFixture.frontpage))
        let model = env.make { GalleryListModel(source: .frontpage) }
        await model.loadIfNeeded()
        #expect(model.pageStarts.isEmpty)
    }

    // MARK: Helpers

    /// Toplists pages 1–10, each with galleries of its own.
    private func serveToplists(on env: ListTestEnvironment) throws {
        env.transport.on(.any, reply: try Self.toplistsPage(1))
        for page in 2...10 {
            env.transport.on(.query("p", "\(page - 1)"), reply: try Self.toplistsPage(page))
        }
    }

    /// The toplists fixture as its 1-based page `page`; its gids get a prefix per page unless
    /// `gidPrefix` says otherwise, so pages do not repeat each other's galleries.
    static func toplistsPage(_ page: Int, gidPrefix: String? = nil) throws -> StubTransport.Reply {
        let current = #"<td class="ptds"><a href="https://e-hentai.org/toplist.php?tl=11" onclick="return false">1</a></td>"#
        var html = try Fixture.string(ListFixture.toplists)
        #expect(html.contains(current))
        html = html.replacingOccurrences(of: current, with: current.replacingOccurrences(of: ">1<", with: ">\(page)<"))
        html = html.replacingOccurrences(of: "/g/", with: "/g/\(gidPrefix ?? "\(page)0")")
        return .html(html)
    }
}
