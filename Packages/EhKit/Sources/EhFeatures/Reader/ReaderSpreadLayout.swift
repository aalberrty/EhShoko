import CoreGraphics

/// Maps 1-based page numbers to the items the paged reader swipes through ("spreads") and back.
///
/// This is a port of the legacy `ReadingReducer.State.containerDataSource`,
/// `imageContainerConfigs` and `PageHandler` and keeps their results exactly, quirks included.
nonisolated public struct ReaderSpreadLayout: Sendable, Equatable {
    public let pageCount: Int
    /// Two pages per spread. Decide it with `ReaderConfiguration.usesDualPage(in:)`.
    public let isDualPage: Bool
    /// Page 1 on its own; only meaningful with dual pages.
    public let exceptCover: Bool
    /// Whether something that is not a page follows the last page (the closing page). It has
    /// no page number: every function below that maps pages and spreads ignores it. An empty
    /// gallery has none.
    public let hasTrailer: Bool

    /// Where the trailer goes among the spreads.
    nonisolated public enum TrailerPlacement: Sendable, Equatable {
        case none
        /// In the empty half of the last spread, which holds one page.
        case besideLastPage(spread: Int)
        /// In a slot of its own after the last spread.
        case ownSlot
    }

    public init(pageCount: Int, isDualPage: Bool, exceptCover: Bool, hasTrailer: Bool = false) {
        self.pageCount = max(pageCount, 0)
        self.isDualPage = isDualPage
        self.exceptCover = isDualPage && exceptCover
        self.hasTrailer = hasTrailer && pageCount > 0
    }

    // MARK: The trailer

    public var trailerPlacement: TrailerPlacement {
        guard hasTrailer, spreadCount > 0 else { return .none }
        let last = spreadCount - 1
        // A cover that is alone by choice stays alone: the trailer does not join it.
        let isCoverAlone = exceptCover && last == 0
        if isDualPage, !isCoverAlone, pages(inSpread: last).count == 1 {
            return .besideLastPage(spread: last)
        }
        return .ownSlot
    }

    /// The places the pager swipes through, in reading order: the spreads, and one more for a
    /// trailer that has a slot of its own. Slot `spreadCount` is then the trailer.
    public var slotCount: Int {
        trailerPlacement == .ownSlot ? spreadCount + 1 : spreadCount
    }

    /// The slot that shows the trailer, counted in reading order like a spread, or `nil`
    /// without one.
    public var trailerSlot: Int? {
        switch trailerPlacement {
        case .none: nil
        case .besideLastPage(let spread): spread
        case .ownSlot: spreadCount
        }
    }

    /// The page number reported as "current" while a slot is showing: a spread's
    /// (`reportedPage(forSpread:)`), and the last page on the trailer's own slot. Whoever is
    /// there has read every page, also where the last spread reports its first page (a
    /// gallery of two pages laid out as one spread).
    public func reportedPage(forSlot index: Int) -> Int {
        if trailerPlacement == .ownSlot, index >= spreadCount { return pageCount }
        return reportedPage(forSpread: index)
    }

    // MARK: Pages and spreads

    public var spreadCount: Int {
        guard pageCount > 0 else { return 0 }
        guard isDualPage else { return pageCount }
        // [1] + stride(2, through: n, by: 2)  or  stride(1, through: n, by: 2)
        return exceptCover ? 1 + pageCount / 2 : (pageCount + 1) / 2
    }

    /// The lowest page number shown by a spread.
    public func firstPage(ofSpread index: Int) -> Int {
        guard isDualPage else { return index + 1 }
        if exceptCover { return index == 0 ? 1 : index * 2 }
        return index * 2 + 1
    }

    /// The pages of a spread in reading order: one or two consecutive page numbers.
    public func pages(inSpread index: Int) -> ClosedRange<Int> {
        let first = firstPage(ofSpread: index)
        let isCoverAlone = exceptCover && index == 0
        guard isDualPage, !isCoverAlone, first + 1 <= pageCount else { return first...first }
        return first...(first + 1)
    }

    /// The pages of a spread as they sit on screen from left to right. Right-to-left reading
    /// swaps the two pages of a spread, so the lower page number is on the right.
    public func pagesOnScreen(inSpread index: Int, rightToLeft: Bool) -> [Int] {
        let pages = pages(inSpread: index)
        return rightToLeft ? pages.reversed() : Array(pages)
    }

    /// The spread that shows a page. Out-of-range pages are clamped.
    public func spreadIndex(forPage page: Int) -> Int {
        guard spreadCount > 0 else { return 0 }
        let index: Int
        if !isDualPage {
            index = page - 1
        } else if page <= 1 {
            index = 0
        } else {
            index = exceptCover ? page / 2 : (page - 1) / 2
        }
        return min(max(index, 0), spreadCount - 1)
    }

    /// The page number reported as "current" while a spread is showing.
    ///
    /// It is the spread's first page, except that a spread whose second page is the last page
    /// of the gallery reports that last page, so progress can reach the end. The very first
    /// spread always reports page 1, as legacy does.
    public func reportedPage(forSpread index: Int) -> Int {
        guard pageCount > 0 else { return 1 }
        guard isDualPage else { return min(max(index + 1, 1), pageCount) }
        guard index > 0 else { return 1 }
        let first = firstPage(ofSpread: index)
        return first + 1 == pageCount ? pageCount : min(first, pageCount)
    }
}
