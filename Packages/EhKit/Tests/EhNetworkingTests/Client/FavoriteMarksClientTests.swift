import EhModels
import EhNetworking
import EhTestSupport
import Foundation
import Testing

/// Folders and marks come from the same page as the galleries; nothing more is requested.
struct FavoriteMarksClientTests {
    private let filter = Filter()

    @Test func favoritesPageCarriesFoldersAndMarks() async throws {
        let harness = ClientHarness()
        harness.transport.on(.any, reply: .fixture(ClientFixture.list("FavoritesMinimalList")))

        let page = try await harness.client.favorites(category: 2)

        #expect(harness.requests.count == 1)
        #expect(page.folders.count == 10)
        #expect(page.folders.first == FavoriteFolder(index: 0, name: "Favorites 0", count: 117))
        #expect(page.favoriteMarks.count == page.galleries.count)
        #expect(page.favoriteMarks["1991004"]?.folder == 2)
        #expect(page.favoriteMarks["1991004"]?.favoritedDate != nil)
    }

    @Test func moreFavoritesCarriesFoldersAndMarks() async throws {
        let harness = ClientHarness()
        harness.transport.on(.any, reply: .fixture(ClientFixture.list("FavoritesExtendedList")))

        let page = try await harness.client.moreFavorites(category: -1, lastID: "1", lastTimestamp: "2")

        #expect(page.folders.map(\.count).reduce(0, +) == 120)
        #expect(page.favoriteMarks.count == 100)
    }

    @Test func listPagesCarryMarks() async throws {
        let harness = ClientHarness()
        let html = try Fixture.string(ClientFixture.list("FrontPageCompactList")).replacingOccurrences(
            of: #"id="posted_2668616""#, with: #"style="border-color:#f00" id="posted_2668616""#
        )
        harness.transport.on(.any, reply: .html(html))

        let frontpage = try await harness.client.frontpage(filter: filter)
        let search = try await harness.client.search(keyword: "x", filter: filter)
        let popular = try await harness.client.popularPage(filter: filter)

        for page in [frontpage, search, popular] {
            #expect(page.favoriteMarks == ["2668616": FavoriteMark(folder: 1)])
        }
    }

    @Test func popularPageIsPopular() async throws {
        let harness = ClientHarness()
        harness.transport.on(.any, reply: .fixture(ClientFixture.list("PopularCompactList")))

        let page = try await harness.client.popularPage(filter: filter)

        #expect(try harness.onlyRequest().url == harness.builder.popularGalleries(filter: filter).url)
        #expect(page.galleries.count == 100)
        #expect(page.favoriteMarks.isEmpty)
    }
}
