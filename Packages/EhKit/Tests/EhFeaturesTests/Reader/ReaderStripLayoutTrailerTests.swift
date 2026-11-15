import CoreGraphics
import Testing
@testable import EhFeatures

/// The trailer (the closing page's block) in the vertical strip. With it on, every page's
/// frame, anchor, scroll target and report must equal the result without it.
@Suite struct ReaderStripLayoutTrailerTests {
    private static let ratios: [CGFloat?] = [1, nil, 0.5, 2, 0.7, 4, nil, 0.1, 0.7]

    private static func makeLayout(
        pageCount: Int = 9, width: CGFloat = 100, gap: CGFloat = 10, trailer: CGFloat = 0
    ) -> ReaderStripLayout {
        var layout = ReaderStripLayout(pageCount: pageCount, width: width, gap: gap, displayScale: 2) {
            ratios[($0 - 1) % ratios.count]
        }
        layout.setTrailerHeight(trailer)
        return layout
    }

    /// Everything the strip view asks about pages, for scroll positions over the pages.
    private static func expectSamePages(_ on: ReaderStripLayout, _ off: ReaderStripLayout, viewport: CGFloat) {
        #expect(on.pageCount == off.pageCount)
        #expect(on.pagesHeight == off.pagesHeight)
        #expect(on.pagesHeight == off.contentHeight)
        #expect(on.maximumPageOffset(viewportHeight: viewport) == off.maximumOffset(viewportHeight: viewport))
        for page in 0...(off.pageCount + 1) {
            #expect(on.frame(ofPage: page) == off.frame(ofPage: page))
            #expect(on.offset(forPage: page, viewportHeight: viewport) == off.offset(forPage: page, viewportHeight: viewport))
        }
        let end = off.maximumOffset(viewportHeight: viewport)
        var y: CGFloat = -20
        while y <= end {
            #expect(on.page(atY: y) == off.page(atY: y))
            #expect(on.anchor(atY: y) == off.anchor(atY: y))
            #expect(on.pages(fromY: y, toY: y + viewport) == off.pages(fromY: y, toY: y + viewport))
            #expect(
                on.pages(fromY: y - viewport / 2, toY: y + viewport * 1.5)
                    == off.pages(fromY: y - viewport / 2, toY: y + viewport * 1.5)
            )
            #expect(
                on.currentPage(viewportMinY: y, viewportHeight: viewport)
                    == off.currentPage(viewportMinY: y, viewportHeight: viewport)
            )
            if let anchor = off.anchor(atY: y) {
                #expect(on.y(for: anchor) == off.y(for: anchor))
            }
            y += 3.5
        }
    }

    @Test func pagesAreUnchangedByATrailer() {
        for pageCount in 0...9 {
            for width in [100, 77.5, 320] as [CGFloat] {
                for gap in [0, 10] as [CGFloat] {
                    for viewport in [60, 180, 700] as [CGFloat] {
                        let off = Self.makeLayout(pageCount: pageCount, width: width, gap: gap)
                        let on = Self.makeLayout(pageCount: pageCount, width: width, gap: gap, trailer: viewport * 0.7)
                        Self.expectSamePages(on, off, viewport: viewport)
                    }
                }
            }
        }
    }

    @Test func changesMoveTheSamePagesTheSameWay() {
        var off = Self.makeLayout()
        var on = Self.makeLayout(trailer: 126)
        // A ratio arrives, the width changes (rotation), the gap changes.
        #expect(on.setAspectRatio(0.5, forPage: 2) == off.setAspectRatio(0.5, forPage: 2))
        Self.expectSamePages(on, off, viewport: 180)
        #expect(on.setAspectRatio(nil, forPage: 9) == off.setAspectRatio(nil, forPage: 9))
        Self.expectSamePages(on, off, viewport: 180)
        on.setWidth(240)
        off.setWidth(240)
        Self.expectSamePages(on, off, viewport: 180)
        on.setGap(0)
        off.setGap(0)
        Self.expectSamePages(on, off, viewport: 180)
        #expect(on.trailerHeight == 126)
    }

    @Test func aTrailersHeightMovesNoPage() {
        let off = Self.makeLayout()
        var on = Self.makeLayout(trailer: 126)
        on.setTrailerHeight(900)
        Self.expectSamePages(on, off, viewport: 180)
        on.setTrailerHeight(0)
        #expect(on == off)
        on.setTrailerHeight(-5)
        #expect(on.trailerHeight == 0)
        on.setTrailerHeight(.infinity)
        #expect(on.trailerHeight == 0)
        on.setTrailerHeight(.nan)
        #expect(on.trailerHeight == 0)
    }

    @Test func theTrailerFollowsTheLastPageAfterAGap() {
        let off = Self.makeLayout(pageCount: 4)
        let on = Self.makeLayout(pageCount: 4, trailer: 126)
        // Pages end at 523 (see `ReaderStripLayoutTests.pagesAreStackedWithGaps`).
        #expect(off.contentHeight == 523)
        #expect(off.trailerFrame == nil)
        #expect(on.trailerFrame == CGRect(x: 0, y: 533, width: 100, height: 126))
        #expect(on.contentHeight == 659)
        #expect(on.maximumOffset(viewportHeight: 180) == 479)
        #expect(on.maximumPageOffset(viewportHeight: 180) == 343)
    }

    @Test func theTrailerMovesWithThePagesAboveIt() {
        var on = Self.makeLayout(pageCount: 4, trailer: 126)
        on.setAspectRatio(1, forPage: 2)
        // Page 2 went from 143 to 100 points.
        #expect(on.trailerFrame == CGRect(x: 0, y: 490, width: 100, height: 126))
        on.setGap(0)
        #expect(on.trailerFrame == CGRect(x: 0, y: 450, width: 100, height: 126))
        on.setWidth(200)
        #expect(on.trailerFrame?.minY == on.frame(ofPage: 4).maxY)
        #expect(on.trailerFrame?.width == 200)
    }

    @Test func aPositionInsideTheTrailerReportsTheLastPage() {
        let on = Self.makeLayout(pageCount: 4, trailer: 126)
        #expect(on.page(atY: 540) == 4)
        #expect(on.page(atY: 658) == 4)
        #expect(on.pages(fromY: 540, toY: 659) == 4...4)
        #expect(on.currentPage(viewportMinY: 479, viewportHeight: 180) == 4)
        #expect(on.currentPage(viewportMinY: 400, viewportHeight: 180) == 4)
        // The bottom edge of the last page: where a resize finds the strip again.
        #expect(on.anchor(atY: 600) == ReaderStripLayout.Anchor(page: 4, fraction: 1))
    }

    @Test func aShortLastPageIsStillReportedAtTheEndOfThePages() {
        // Page 4 is 50 points tall in a 180 point viewport: resting against the end of the
        // pages reports it, with or without a trailer, although the middle is on page 3.
        let off = Self.makeLayout(pageCount: 4)
        let on = Self.makeLayout(pageCount: 4, trailer: 126)
        #expect(off.currentPage(viewportMinY: 343, viewportHeight: 180) == 4)
        #expect(on.currentPage(viewportMinY: 343, viewportHeight: 180) == 4)
        #expect(on.currentPage(viewportMinY: 342, viewportHeight: 180) == 3)
        #expect(on.currentPage(viewportMinY: 380, viewportHeight: 180) == 4)
    }

    @Test func goingToTheLastPageDoesNotShowTheTrailer() {
        let on = Self.makeLayout(pageCount: 4, trailer: 126)
        let offset = on.offset(forPage: 4, viewportHeight: 180)
        #expect(offset == 343)
        #expect(offset + 180 <= on.trailerFrame?.minY ?? 0)
        #expect(!on.isTrailerCurrent(viewportMinY: offset, viewportHeight: 180))
    }

    @Test func theTrailerIsShownCentredOrFromItsTop() {
        // Shorter than the viewport: centred, which the end of the strip limits.
        let short = Self.makeLayout(pageCount: 4, trailer: 126)
        #expect(short.trailerOffset(viewportHeight: 180) == 479)
        // Taller than the viewport: from its top.
        let tall = Self.makeLayout(pageCount: 4, trailer: 400)
        #expect(tall.trailerOffset(viewportHeight: 180) == 533)
        #expect(Self.makeLayout(pageCount: 4).trailerOffset(viewportHeight: 180) == nil)
    }

    /// Wherever the strip is sent to show the trailer, the trailer is what the reader is on.
    @Test func theTrailerIsCurrentWhereItIsShown() {
        for pageCount in 1...9 {
            for viewport in [60, 180, 700] as [CGFloat] {
                for trailer in [viewport * 0.7, viewport, viewport * 2.5] {
                    let on = Self.makeLayout(pageCount: pageCount, trailer: trailer)
                    let offset = on.trailerOffset(viewportHeight: viewport)
                    #expect(offset.map { on.isTrailerCurrent(viewportMinY: $0, viewportHeight: viewport) } == true)
                }
            }
        }
    }

    @Test func theTrailerIsCurrentUnderTheMiddleOfTheViewport() {
        let on = Self.makeLayout(pageCount: 4, trailer: 126)
        // Its top is at 533; the middle of a 180 point viewport reaches it at 443.
        #expect(!on.isTrailerCurrent(viewportMinY: 442, viewportHeight: 180))
        #expect(on.isTrailerCurrent(viewportMinY: 443, viewportHeight: 180))
        #expect(on.isTrailerCurrent(viewportMinY: 479, viewportHeight: 180))
        #expect(!Self.makeLayout(pageCount: 4).isTrailerCurrent(viewportMinY: 343, viewportHeight: 180))
    }

    @Test func aStripThatFitsOnScreenIsAtItsEnd() {
        // One wide page and the trailer, both on screen with nothing to scroll.
        let on = Self.makeLayout(pageCount: 1, trailer: 100)
        #expect(on.contentHeight == 210)
        #expect(on.maximumOffset(viewportHeight: 600) == 0)
        #expect(on.isTrailerCurrent(viewportMinY: 0, viewportHeight: 600))
        #expect(on.currentPage(viewportMinY: 0, viewportHeight: 600) == 1)
    }

    @Test func anEmptyStripHasNoTrailer() {
        let on = Self.makeLayout(pageCount: 0, trailer: 126)
        #expect(on.trailerFrame == nil)
        #expect(on.contentHeight == 0)
        #expect(on.trailerOffset(viewportHeight: 180) == nil)
        #expect(!on.isTrailerCurrent(viewportMinY: 0, viewportHeight: 180))
    }
}
