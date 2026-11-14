import EhModels
import EhTestSupport
import Foundation
import Testing
@testable import EhParser

@Suite struct FavoriteParserTests {
    static let favoritesFixtures: [ListFixture] = [
        .favoritesMinimalList, .favoritesMinimalPlusList, .favoritesCompactList,
        .favoritesExtendedList, .favoritesThumbnailList
    ]

    @Test(arguments: favoritesFixtures)
    func foldersHaveNamesAndCounts(fixture: ListFixture) throws {
        let folders = Parser.parseFavoriteFolders(doc: try parserFixture(fixture.path))
        #expect(folders.map(\.index) == Array(0...9))
        #expect(folders.map(\.name) == (0...9).map { "Favorites \($0)" })
        #expect(folders.map(\.count) == [117, 2, 1, 0, 0, 0, 0, 0, 0, 0])
    }

    @Test func foldersUseTheUsersNamesAndLargeCounts() throws {
        let block = { (index: Int, count: String, name: String) in
            """
            <div class="fp" onclick="document.location='https://e-hentai.org/favorites.php?favcat=\(index)'">
            <div style="font-weight:bold">\(count)</div><div class="i" title="\(name)"></div>
            <div style="float:left"> \(name) </div></div>
            """
        }
        let document = try html("""
        <html><body>\(block(3, "1,284", "To read"))\(block(0, "7", "Best"))
        <div class="fp fps" onclick="document.location='https://e-hentai.org/favorites.php'">Show All Favorites</div>
        </body></html>
        """)
        let folders = Parser.parseFavoriteFolders(doc: document)
        #expect(folders == [
            FavoriteFolder(index: 0, name: "Best", count: 7),
            FavoriteFolder(index: 3, name: "To read", count: 1284)
        ])
    }

    @Test(arguments: [ListFixture.frontPageCompactList, .watchedExtendedList, .toplistsCompactList])
    func listsWithoutFolderBlocksHaveNone(fixture: ListFixture) throws {
        #expect(Parser.parseFavoriteFolders(doc: try parserFixture(fixture.path)).isEmpty)
    }

    @Test(arguments: favoritesFixtures)
    func everyGalleryOnAFavoritesPageIsMarked(fixture: ListFixture) throws {
        let document = try parserFixture(fixture.path)
        let galleries = try Parser.parseGalleries(doc: document)
        let marks = Parser.parseFavoriteMarks(doc: document)
        #expect(Set(marks.keys) == Set(galleries.map(\.gid)))
        let folders = Dictionary(grouping: marks.values, by: \.folder).mapValues(\.count)
        #expect(folders == [0: 97, 1: 2, 2: 1])
        #expect(marks["1991004"]?.folder == 2)
        #expect(marks["2079308"]?.folder == 1)
        #expect(marks["2636342"]?.folder == 0)
    }

    @Test(arguments: favoritesFixtures)
    func favoritedDatesInEveryModeButThumbnail(fixture: ListFixture) throws {
        let marks = Parser.parseFavoriteMarks(doc: try parserFixture(fixture.path))
        if fixture == .favoritesThumbnailList {
            #expect(marks.values.allSatisfy { $0.favoritedDate == nil })
        } else {
            #expect(marks.values.allSatisfy { $0.favoritedDate != nil })
            #expect(marks["2636342"]?.favoritedDate == utcDate(2023, 7, 6, 1, 41))
            #expect(marks["1991004"]?.favoritedDate == utcDate(2022, 1, 19, 8, 46))
        }
    }

    @Test(arguments: ListFixture.allCases.filter { !FavoriteParserTests.favoritesFixtures.contains($0) })
    func aPageWithNoFavoritedItemHasNoMarks(fixture: ListFixture) throws {
        #expect(Parser.parseFavoriteMarks(doc: try parserFixture(fixture.path)).isEmpty)
    }

    /// Outside favourites the site marks a favourited gallery's date the same way, without a
    /// favourited date.
    @Test(arguments: [ListFixture.frontPageCompactList, .frontPageExtendedList, .frontPageThumbnailList])
    func aFavoritedGalleryOnAnotherListIsMarked(fixture: ListFixture) throws {
        let original = try Fixture.string("Parser/\(fixture.path)")
        let marked = original.replacingOccurrences(
            of: #"id="posted_2668616""#,
            with: #"style="border-color:#4bf;background-color:rgba(0,0,0,.1)" id="posted_2668616" title="Doujin""#
        )
        #expect(marked != original)
        let marks = Parser.parseFavoriteMarks(doc: try html(marked))
        #expect(marks == ["2668616": FavoriteMark(folder: 6)])
    }

    @Test func folderColours() {
        let styles = ["000", "f00", "fa0", "dd0", "080", "9f4", "4bf", "00f", "508", "e8e"]
        for (index, hex) in styles.enumerated() {
            #expect(ListParser.parseFavoriteFolder(style: "border-color:#\(hex);background-color:x") == index)
        }
        #expect(ListParser.parseFavoriteFolder(style: "border-color:#FFAA00") == 2)
        #expect(ListParser.parseFavoriteFolder(style: "border-color:#1357df;background:x") == nil)
        #expect(ListParser.parseFavoriteFolder(style: "border-color:#123") == nil)
        #expect(ListParser.parseFavoriteFolder(style: "color:#000") == nil)
    }
}
