import EhModels
import Foundation
import Testing
@testable import EhFeatures

@Suite struct RankedPagesTests {
    private func entries(_ count: Int) -> [GalleryEntry] {
        (0..<count).map { GalleryEntry(gallery: .stub("\($0)"), now: Date(timeIntervalSince1970: 0)) }
    }

    @Test func oneUnnumberedPageIsRankedFromOne() {
        let pages = RankedPages(entries: entries(4), pageStarts: [], findText: "")

        #expect(pages.first.map(\.rank) == [1, 2, 3, 4])
        #expect(pages.later.isEmpty)
        #expect(pages.sections == [4])
    }

    @Test func findLeavesTheRanksUnknown() {
        let pages = RankedPages(entries: entries(3), pageStarts: [], findText: "word")

        #expect(pages.first.map(\.rank) == [nil, nil, nil])
    }

    @Test func laterPagesComeWithTheirNumbersAndRanks() {
        let starts = [PageStart(page: 1, index: 0), PageStart(page: 2, index: 3), PageStart(page: 3, index: 6)]

        let pages = RankedPages(entries: entries(8), pageStarts: starts, findText: "")

        #expect(pages.first.map(\.rank) == [1, 2, 3])
        #expect(pages.later.map(\.number) == [2, 3])
        #expect(pages.later.map(\.index) == [1, 2])
        #expect(pages.later.map { $0.rows.map(\.rank) } == [[4, 5, 6], [7, 8]])
        #expect(pages.sections == [3, 3, 2])
        #expect(pages.later[1].rows.map(\.id) == ["6", "7"])
    }

    /// Opened at page 5 of 50 a page, the first gallery is 201st.
    @Test func aListOpenedLaterCountsFromItsPage() {
        let pages = RankedPages(entries: entries(2), pageStarts: [PageStart(page: 5, index: 0)], findText: "")

        #expect(pages.first.map(\.rank) == [201, 202])
    }

    @Test func thePageSizeIsTheDistanceBetweenTheFirstTwoPages() {
        #expect(RankedPages.pageSize(of: []) == 50)
        #expect(RankedPages.pageSize(of: [PageStart(page: 1, index: 0)]) == 50)
        #expect(RankedPages.pageSize(of: [PageStart(page: 1, index: 0), PageStart(page: 2, index: 25)]) == 25)
        // Two starts at one place say nothing about the size.
        #expect(RankedPages.pageSize(of: [PageStart(page: 1, index: 0), PageStart(page: 2, index: 0)]) == 50)
        #expect(RankedPages.firstRank(ofPage: 3, pageSize: 25) == 51)
    }

    /// Page starts past the loaded entries (a page that came back empty) give empty pages, not
    /// a crash.
    @Test func startsPastTheEntriesGiveEmptyPages() {
        let starts = [PageStart(page: 1, index: 0), PageStart(page: 2, index: 2), PageStart(page: 3, index: 9)]

        let pages = RankedPages(entries: entries(3), pageStarts: starts, findText: "")

        #expect(pages.sections == [2, 1, 0])
    }
}
