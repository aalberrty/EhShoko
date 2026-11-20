import CoreGraphics
import Foundation
import Testing
@testable import EhFeatures

@Suite struct ListPageSpansTests {
    /// Three columns, rows 100 high, dividers 30: a page of 25 has nine rows and is 900 high.
    private func spans(_ pages: [Int] = [25, 25, 25, 10], divider: CGFloat = 30) -> ListPageSpans {
        ListPageSpans(pages: pages, columns: 3, rowHeight: 100, dividerHeight: divider)
    }

    // MARK: Where a page stands

    @Test func aPageIsAsHighAsItsRows() {
        let spans = spans()
        #expect(spans.count == 4)
        #expect(spans.height(ofPage: 0) == 900)
        // Ten entries in three columns: the fourth row holds one.
        #expect(spans.height(ofPage: 3) == 400)
        #expect(spans.entries(inPage: 0) == 25)
        #expect(spans.entries(inPage: 3) == 10)
    }

    @Test func everyLaterPageStandsUnderADivider() {
        let spans = spans()
        #expect(spans.top(ofPage: 0) == 0)
        #expect(spans.top(ofPage: 1) == 930)
        #expect(spans.top(ofPage: 2) == 1_860)
        #expect(spans.top(ofPage: 3) == 2_790)
        #expect(spans.height == 3_190)
    }

    @Test func withoutDividersThePagesFollowEachOther() {
        let spans = spans([6, 6], divider: 0)
        #expect(spans.top(ofPage: 1) == 200)
        #expect(spans.height == 400)
    }

    @Test func anEmptyPageHasNoHeightButItsDivider() {
        let spans = spans([6, 0, 3])
        #expect(spans.height(ofPage: 1) == 0)
        #expect(spans.top(ofPage: 1) == 230)
        #expect(spans.top(ofPage: 2) == 260)
        #expect(spans.height == 360)
    }

    @Test func aPageOutOfRangeHoldsNothing() {
        let spans = spans()
        #expect(spans.entries(inPage: -1) == 0)
        #expect(spans.entries(inPage: 4) == 0)
        #expect(spans.height(ofPage: 9) == 0)
        // The nearest page's top.
        #expect(spans.top(ofPage: -3) == 0)
        #expect(spans.top(ofPage: 9) == 2_790)
    }

    @Test func noPagesHaveNoHeight() {
        let spans = spans([])
        #expect(spans.count == 0)
        #expect(spans.height == 0)
        #expect(spans.top(ofPage: 0) == 0)
        #expect(spans.page(ofEntry: 0) == nil)
        #expect(spans.pages(near: 0...800, reach: 800).isEmpty)
    }

    @Test func columnsAreAtLeastOne() {
        let spans = ListPageSpans(pages: [4], columns: 0, rowHeight: 50)
        #expect(spans.columns == 1)
        #expect(spans.height == 200)
    }

    @Test func anEntryIsInThePageThatStartsAtOrBeforeIt() {
        let spans = spans()
        #expect(spans.page(ofEntry: 0) == 0)
        #expect(spans.page(ofEntry: 24) == 0)
        #expect(spans.page(ofEntry: 25) == 1)
        #expect(spans.page(ofEntry: 84) == 3)
        // Out of range: the nearest entry's page.
        #expect(spans.page(ofEntry: -4) == 0)
        #expect(spans.page(ofEntry: 500) == 3)
    }

    @Test func anEntryAfterAnEmptyPageIsInTheNextOne() {
        // Page 1 holds nothing: entry 6 is page 2's first.
        #expect(spans([6, 0, 3]).page(ofEntry: 6) == 2)
    }

    // MARK: The pages near the part on screen

    @Test func thePagesOnScreenAreNear() {
        let spans = spans()
        // Inside the first page.
        #expect(spans.pages(near: 100...700) == 0..<1)
        // Across the first divider.
        #expect(spans.pages(near: 600...1_400) == 0..<2)
        // Inside the third page.
        #expect(spans.pages(near: 2_000...2_700) == 2..<3)
    }

    @Test func aPageCountsFromItsDividerToUnderItsLastRow() {
        let spans = spans()
        // The second page's divider starts at 900, where the first page's rows end.
        #expect(spans.pages(near: 0...899) == 0..<1)
        #expect(spans.pages(near: 0...900) == 0..<2)
        #expect(spans.pages(near: 901...1_000) == 1..<2)
        #expect(spans.pages(near: 900...1_000) == 0..<2)
    }

    @Test func theReachAddsToBothEnds() {
        let spans = spans()
        #expect(spans.pages(near: 1_000...1_700, reach: 0) == 1..<2)
        // 200 above is where the first page's rows end, 200 below the third page's divider.
        #expect(spans.pages(near: 1_100...1_700, reach: 200) == 0..<3)
        #expect(spans.pages(near: 1_101...1_629, reach: 200) == 1..<2)
        // A reach below zero counts as none.
        #expect(spans.pages(near: 1_000...1_700, reach: -500) == 1..<2)
    }

    @Test func everythingIsNearAScreenThatHoldsItAll() {
        #expect(spans().pages(near: 0...800, reach: 5_000) == 0..<4)
    }

    @Test func aStretchOutsideThePagesGivesTheNearestPage() {
        let spans = spans()
        // Above the first row: a header is on screen.
        #expect(spans.pages(near: -2_000...(-1_200)) == 0..<1)
        // Below the last row: the footer, or a scroll view pulled past its end.
        #expect(spans.pages(near: 4_000...4_800) == 3..<4)
    }

    @Test func anEmptyPageBetweenTwoIsNearWithThem() {
        let spans = spans([6, 0, 3])
        #expect(spans.pages(near: 150...300) == 0..<3)
        #expect(spans.pages(near: 0...100) == 0..<1)
    }

    @Test func onePageIsAlwaysNear() {
        let spans = spans([40])
        #expect(spans.pages(near: 0...10) == 0..<1)
        #expect(spans.pages(near: 9_000...9_800, reach: 100) == 0..<1)
    }

    // MARK: The pages to draw

    @Test func aQuarterOfAScreenBeyondEachEdgeIsDrawn() {
        // Pages 1,000 high with dividers of 30, a screen 1,200 high.
        let spans = ListPageSpans(pages: [30, 30, 30, 30, 30, 30], columns: 3, rowHeight: 100, dividerHeight: 30)
        #expect(ListPageSpans.reachScreens == 0.25)
        // From 2,400 to 3,600, with 300 beyond each edge: 2,100 to 3,900. The second page ends
        // at 2,030 and the fifth page's divider starts at 4,090.
        #expect(spans.pages(onScreensAt: [2_400], height: 1_200) == IndexSet(integersIn: 2..<4))
        // At the top, the first two pages.
        #expect(spans.pages(onScreensAt: [0], height: 1_200) == IndexSet(integersIn: 0..<2))
    }

    @Test func aLowScreenStillReachesTheLeast() {
        let spans = ListPageSpans(pages: [30, 30, 30, 30], columns: 3, rowHeight: 100, dividerHeight: 30)
        #expect(ListPageSpans.leastReach == 200)
        // Nothing known of the screen yet: 200 on from the top is still the first page.
        #expect(spans.pages(onScreensAt: [0], height: 0) == IndexSet(integersIn: 0..<1))
        // From 700 to 900, with 200 beyond: the second page's divider starts at 1,000.
        #expect(spans.pages(onScreensAt: [700], height: 200) == IndexSet(integersIn: 0..<2))
        // A height below zero counts as none: 500 to 900.
        #expect(spans.pages(onScreensAt: [700], height: -40) == IndexSet(integersIn: 0..<1))
    }

    /// A density change sends the list elsewhere: what is near where it is going is drawn
    /// with what is near where it still is, and nothing between the two.
    @Test func twoPlacesGiveThePagesNearEach() {
        let spans = ListPageSpans(pages: Array(repeating: 30, count: 12), columns: 3, rowHeight: 100, dividerHeight: 30)
        let pages = spans.pages(onScreensAt: [9_500, 1_200], height: 800)
        #expect(pages == IndexSet(integersIn: 0..<3).union(IndexSet(integersIn: 9..<11)))
        #expect(spans.pages(onScreensAt: [], height: 800).isEmpty)
    }

    // MARK: Asking for the next page

    /// Four pages, 4,090 high together; a screen 800 high asks from 1,200 before its lower
    /// edge reaches the end: with its top edge at 2,090.
    @Test func theNextPageIsAskedForAScreenAndAHalfBeforeTheEnd() {
        let spans = ListPageSpans(pages: [30, 30, 30, 30], columns: 3, rowHeight: 100, dividerHeight: 30)
        #expect(spans.height == 4_090)
        #expect(ListPageSpans.leadScreens == 1.5)
        #expect(!spans.drawn(onScreensAt: [0], height: 800).asksForMore)
        #expect(!spans.drawn(onScreensAt: [2_089], height: 800).asksForMore)
        #expect(spans.drawn(onScreensAt: [2_090], height: 800).asksForMore)
        #expect(spans.drawn(onScreensAt: [3_290], height: 800).asksForMore)
        // Pulled past the end.
        #expect(spans.drawn(onScreensAt: [3_500], height: 800).asksForMore)
    }

    @Test func aShortListAsksAtOnce() {
        // One page of two rows under a screen of 800: its end is on screen.
        let spans = ListPageSpans(pages: [6], columns: 3, rowHeight: 100)
        #expect(spans.drawn(onScreensAt: [-60], height: 800).asksForMore)
        // No pages at all: the end is where the top is.
        #expect(ListPageSpans(pages: [], columns: 3, rowHeight: 100).drawn(onScreensAt: [0], height: 800).asksForMore)
    }

    @Test func nothingIsAskedForBeforeTheScreenIsKnown() {
        let spans = ListPageSpans(pages: [6], columns: 3, rowHeight: 100)
        #expect(!spans.drawn(onScreensAt: [0], height: 0).asksForMore)
        #expect(!spans.drawn(onScreensAt: [], height: 800).asksForMore)
        // The pages are drawn all the same.
        #expect(spans.drawn(onScreensAt: [0], height: 0).pages == IndexSet(integer: 0))
    }

    /// A density change sends the list near its end: asked for at once, with the pages drawn.
    @Test func aPlaceTheListIsSentToAsksToo() {
        let spans = ListPageSpans(pages: Array(repeating: 30, count: 12), columns: 3, rowHeight: 100, dividerHeight: 30)
        let drawn = spans.drawn(onScreensAt: [1_200, 11_000], height: 800)
        #expect(drawn.asksForMore)
        #expect(drawn.pages == spans.pages(onScreensAt: [1_200, 11_000], height: 800))
        #expect(!spans.drawn(onScreensAt: [1_200, 5_000], height: 800).asksForMore)
    }

    /// The pages drawn while the list scrolls from its top to its end leave no gap: whatever
    /// is on screen is in a page that is near.
    @Test func noPartOnScreenIsEverOutsideTheNearPages() {
        let spans = spans([25, 25, 7, 0, 25, 1, 25])
        let screen: CGFloat = 640
        for top in stride(from: -300 as CGFloat, through: spans.height + 300, by: 7) {
            let near = spans.pages(near: top...(top + screen), reach: 50)
            for page in 0..<spans.count {
                let from = spans.top(ofPage: page) - (page > 0 ? spans.dividerHeight : 0)
                let through = spans.top(ofPage: page) + spans.height(ofPage: page)
                let isOnScreen = through >= top && from <= top + screen
                if isOnScreen {
                    #expect(near.contains(page))
                }
            }
            #expect(!near.isEmpty)
        }
    }
}
