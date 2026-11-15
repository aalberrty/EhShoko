import CoreGraphics
import Testing
@testable import EhFeatures

/// The trailer (the closing page's slot) in the paged layout. With it on, everything that
/// maps pages and spreads must answer exactly what it answers without it.
@Suite struct ReaderSpreadLayoutTrailerTests {
    private static let pageCounts = Array(0...9) + [40, 41]
    private static let flags = [false, true]

    private static func layouts(_ pageCount: Int, _ isDualPage: Bool, _ exceptCover: Bool)
        -> (off: ReaderSpreadLayout, on: ReaderSpreadLayout) {
        (
            ReaderSpreadLayout(pageCount: pageCount, isDualPage: isDualPage, exceptCover: exceptCover),
            ReaderSpreadLayout(pageCount: pageCount, isDualPage: isDualPage, exceptCover: exceptCover, hasTrailer: true)
        )
    }

    @Test func pagesAndSpreadsAreUnchangedByATrailer() {
        for pageCount in Self.pageCounts {
            for isDualPage in Self.flags {
                for exceptCover in Self.flags {
                    let (off, on) = Self.layouts(pageCount, isDualPage, exceptCover)
                    #expect(on.pageCount == off.pageCount)
                    #expect(on.spreadCount == off.spreadCount)
                    for spread in 0..<off.spreadCount {
                        #expect(on.firstPage(ofSpread: spread) == off.firstPage(ofSpread: spread))
                        #expect(on.pages(inSpread: spread) == off.pages(inSpread: spread))
                        #expect(on.reportedPage(forSpread: spread) == off.reportedPage(forSpread: spread))
                        #expect(on.reportedPage(forSlot: spread) == off.reportedPage(forSpread: spread))
                        for rightToLeft in Self.flags {
                            #expect(
                                on.pagesOnScreen(inSpread: spread, rightToLeft: rightToLeft)
                                    == off.pagesOnScreen(inSpread: spread, rightToLeft: rightToLeft)
                            )
                        }
                    }
                    for page in -1...(pageCount + 2) {
                        #expect(on.spreadIndex(forPage: page) == off.spreadIndex(forPage: page))
                    }
                }
            }
        }
    }

    @Test func withoutATrailerThereIsNoSlotForIt() {
        for pageCount in Self.pageCounts {
            for isDualPage in Self.flags {
                for exceptCover in Self.flags {
                    let (off, _) = Self.layouts(pageCount, isDualPage, exceptCover)
                    #expect(!off.hasTrailer)
                    #expect(off.trailerPlacement == .none)
                    #expect(off.slotCount == off.spreadCount)
                    #expect(off.trailerSlot == nil)
                    // Past the last spread the answer is the last spread's, as it was.
                    #expect(off.reportedPage(forSlot: off.spreadCount) == off.reportedPage(forSpread: off.spreadCount))
                }
            }
        }
    }

    @Test func singlePagesGiveTheTrailerItsOwnSlot() {
        for pageCount in Self.pageCounts where pageCount > 0 {
            let (_, on) = Self.layouts(pageCount, false, false)
            #expect(on.trailerPlacement == .ownSlot)
            #expect(on.slotCount == pageCount + 1)
            #expect(on.trailerSlot == pageCount)
        }
    }

    @Test func twoPagesPutTheTrailerBesideALastPageThatIsAlone() {
        // No cover alone: 1 2 | 3 4 | … An odd count leaves the last page alone.
        for pageCount in Self.pageCounts where pageCount > 0 {
            let (_, on) = Self.layouts(pageCount, true, false)
            if pageCount % 2 == 1 {
                #expect(on.trailerPlacement == .besideLastPage(spread: on.spreadCount - 1))
                #expect(on.slotCount == on.spreadCount)
                #expect(on.trailerSlot == on.spreadCount - 1)
                #expect(on.pages(inSpread: on.spreadCount - 1) == pageCount...pageCount)
            } else {
                #expect(on.trailerPlacement == .ownSlot)
                #expect(on.slotCount == on.spreadCount + 1)
                #expect(on.trailerSlot == on.spreadCount)
            }
        }
    }

    @Test func aCoverThatIsAloneStaysAlone() {
        // Cover alone: 1 | 2 3 | 4 5 | … An even count leaves the last page alone.
        for pageCount in Self.pageCounts where pageCount > 0 {
            let (_, on) = Self.layouts(pageCount, true, true)
            if pageCount == 1 {
                // The cover, then the trailer on its own.
                #expect(on.trailerPlacement == .ownSlot)
                #expect(on.slotCount == 2)
                #expect(on.trailerSlot == 1)
            } else if pageCount % 2 == 0 {
                #expect(on.trailerPlacement == .besideLastPage(spread: on.spreadCount - 1))
                #expect(on.slotCount == on.spreadCount)
            } else {
                #expect(on.trailerPlacement == .ownSlot)
                #expect(on.slotCount == on.spreadCount + 1)
            }
        }
    }

    @Test func anEmptyGalleryHasNoTrailer() {
        for isDualPage in Self.flags {
            let (_, on) = Self.layouts(0, isDualPage, false)
            #expect(!on.hasTrailer)
            #expect(on.trailerPlacement == .none)
            #expect(on.slotCount == 0)
            #expect(on.trailerSlot == nil)
            #expect(on.reportedPage(forSlot: 0) == 1)
        }
    }

    @Test func theTrailersOwnSlotIsAfterTheLastSpreadInReadingOrder() {
        let (_, on) = Self.layouts(5, false, false)
        // Left to right it is the last slot from the left; right to left, the first.
        #expect(ReaderGeometry.slot(forSpread: 5, spreadCount: on.slotCount, rightToLeft: false) == 5)
        #expect(ReaderGeometry.slot(forSpread: 5, spreadCount: on.slotCount, rightToLeft: true) == 0)
        #expect(ReaderGeometry.slot(forSpread: 4, spreadCount: on.slotCount, rightToLeft: true) == 1)
        #expect(ReaderGeometry.spread(forSlot: 0, spreadCount: on.slotCount, rightToLeft: true) == 5)
    }

    /// The trailer has no number of its own: on its slot the reader is on the last page.
    @Test func theTrailersOwnSlotReportsTheLastPage() {
        for pageCount in Self.pageCounts where pageCount > 0 {
            for isDualPage in Self.flags {
                for exceptCover in Self.flags {
                    let (_, on) = Self.layouts(pageCount, isDualPage, exceptCover)
                    guard on.trailerPlacement == .ownSlot else { continue }
                    #expect(on.reportedPage(forSlot: on.spreadCount) == pageCount)
                }
            }
        }
    }

    /// Two pages laid out as one spread report page 1, as legacy does, so the gallery would
    /// never count as read. On the trailer it does.
    @Test func aGalleryOfTwoPagesInOneSpreadIsFinishedOnTheTrailer() {
        let (off, on) = Self.layouts(2, true, false)
        #expect(off.spreadCount == 1)
        #expect(off.reportedPage(forSpread: 0) == 1)
        #expect(on.reportedPage(forSlot: 0) == 1)
        #expect(on.trailerPlacement == .ownSlot)
        #expect(on.reportedPage(forSlot: 1) == 2)
    }

    /// Everywhere else the last spread already reports the last page, so stepping onto the
    /// trailer changes no page number.
    @Test func steppingOntoTheTrailerKeepsThePageExceptForTwoPagesInOneSpread() {
        for pageCount in Self.pageCounts where pageCount > 0 {
            for isDualPage in Self.flags {
                for exceptCover in Self.flags {
                    let (_, on) = Self.layouts(pageCount, isDualPage, exceptCover)
                    guard on.trailerPlacement == .ownSlot else { continue }
                    let last = on.reportedPage(forSlot: on.spreadCount - 1)
                    let isTwoPagesInOneSpread = pageCount == 2 && isDualPage && !exceptCover
                    #expect((last == on.reportedPage(forSlot: on.spreadCount)) == !isTwoPagesInOneSpread)
                }
            }
        }
    }

    @Test func besideTheLastPageTheSpreadReportsTheLastPage() {
        for pageCount in Self.pageCounts where pageCount > 0 {
            for exceptCover in Self.flags {
                let (_, on) = Self.layouts(pageCount, true, exceptCover)
                guard case .besideLastPage(let spread) = on.trailerPlacement else { continue }
                #expect(on.reportedPage(forSlot: spread) == pageCount)
            }
        }
    }

    @Test func aTrailerMakesALayoutDifferent() {
        let (off, on) = Self.layouts(5, false, false)
        #expect(off != on)
    }
}
