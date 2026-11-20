import CoreGraphics
import Foundation

/// Where the pages of a list stand down its scrolling content, measured from the top edge of
/// its first row: each page's entries in rows of one given height, and above each later page
/// a divider of a given height.
///
/// A numbered list draws each page as a grid of its own, and only the pages near the part on
/// screen: the others are blank space of their height (`pages(near:reach:)`). Every height is
/// given and none is measured, so where a page stands is arithmetic and no lazy container has
/// to guess it.
nonisolated public struct ListPageSpans: Sendable, Equatable {
    public let columns: Int
    public let rowHeight: CGFloat
    public let dividerHeight: CGFloat
    /// The index of each page's first entry.
    let starts: [Int]
    /// The top edge of each page's first row.
    let tops: [CGFloat]
    /// How many entries the pages hold together.
    let entryCount: Int
    /// From the first row's top edge to under the last row.
    public let height: CGFloat

    /// - Parameters:
    ///   - pages: how many entries each page holds, in order.
    ///   - columns: how many entries share a row.
    ///   - rowHeight: from one row's top edge to the next row's.
    ///   - dividerHeight: the height of what stands above each page but the first.
    public init(pages: [Int], columns: Int, rowHeight: CGFloat, dividerHeight: CGFloat = 0) {
        self.columns = max(columns, 1)
        self.rowHeight = rowHeight
        self.dividerHeight = dividerHeight
        var starts: [Int] = []
        var tops: [CGFloat] = []
        starts.reserveCapacity(pages.count)
        tops.reserveCapacity(pages.count)
        var index = 0
        var y: CGFloat = 0
        for (offset, page) in pages.enumerated() {
            let entries = max(page, 0)
            if offset > 0 { y += dividerHeight }
            starts.append(index)
            tops.append(y)
            index += entries
            y += CGFloat(Self.rows(entries, columns: self.columns)) * rowHeight
        }
        self.starts = starts
        self.tops = tops
        entryCount = index
        height = y
    }

    /// How many pages there are.
    public var count: Int { starts.count }

    /// How many entries `page` holds.
    public func entries(inPage page: Int) -> Int {
        guard starts.indices.contains(page) else { return 0 }
        return (page + 1 < starts.count ? starts[page + 1] : entryCount) - starts[page]
    }

    /// The top edge of `page`'s first row.
    public func top(ofPage page: Int) -> CGFloat {
        guard !tops.isEmpty else { return 0 }
        return tops[min(max(page, 0), tops.count - 1)]
    }

    /// How high `page`'s rows are together, without its divider.
    public func height(ofPage page: Int) -> CGFloat {
        CGFloat(Self.rows(entries(inPage: page), columns: columns)) * rowHeight
    }

    /// The page that holds the entry at `index`: the nearest one when `index` is out of range,
    /// `nil` without pages.
    public func page(ofEntry index: Int) -> Int? {
        guard !starts.isEmpty else { return nil }
        let clamped = min(max(index, 0), max(entryCount - 1, 0))
        // The last page that starts at or before the entry.
        return max(Self.firstIndex(in: starts.count) { starts[$0] > clamped } - 1, 0)
    }

    /// The pages to draw while `stretch` of the content is on screen: those of which any part,
    /// their divider included, lies in it or within `reach` of it. A stretch above the first
    /// page gives the first and one below the last gives the last, so that the answer is
    /// empty only without pages.
    public func pages(near stretch: ClosedRange<CGFloat>, reach: CGFloat = 0) -> Range<Int> {
        guard !tops.isEmpty else { return 0..<0 }
        let reach = max(reach, 0)
        let from = stretch.lowerBound - reach
        let through = stretch.upperBound + reach
        // The first page that ends at or below `from`, and the first that starts below `through`.
        let lower = Self.firstIndex(in: tops.count) { tops[$0] + height(ofPage: $0) >= from }
        let upper = Self.firstIndex(in: tops.count) { tops[$0] - ($0 > 0 ? dividerHeight : 0) > through }
        let first = min(lower, tops.count - 1)
        return first..<max(upper, first + 1)
    }

    /// How far beyond the screen's edges a page is drawn: this share of the screen's height,
    /// and `leastReach` at least. Far enough that a page is there before a scroll brings it
    /// on screen, and no further: a page's grid measures its first row when it is made, and
    /// made much before that row is needed, the work came on top of another row's.
    public static let reachScreens: CGFloat = 0.25
    public static let leastReach: CGFloat = 200

    /// The pages to draw for a scroll view `height` high that shows the content from each of
    /// `tops` down: where it is and, when it has been sent somewhere else and not been seen
    /// there yet, that place too, each with what is within the reach of its edges.
    public func pages(onScreensAt tops: [CGFloat], height: CGFloat) -> IndexSet {
        let height = max(height, 0)
        let reach = max(height * Self.reachScreens, Self.leastReach)
        var pages = IndexSet()
        for top in tops {
            pages.insert(integersIn: self.pages(near: top...(top + height), reach: reach))
        }
        return pages
    }

    /// What a list of pages draws for where its scroll view is.
    public struct Drawn: Equatable, Sendable {
        /// The pages that are drawn; the others are blank space.
        public var pages = IndexSet()
        /// The end of the pages is on screen or soon will be: the next page is asked for.
        public var asksForMore = false

        public init() {}
    }

    /// How many screens' heights before the end of the pages reaches the screen's lower edge
    /// the next page is asked for: early enough that someone who scrolls on finds it there.
    /// The one grid a numbered list had before built its footer about as far ahead.
    public static let leadScreens: CGFloat = 1.5

    /// What to draw for a scroll view `height` high that shows the content from each of `tops`
    /// down (see `pages(onScreensAt:height:)`), and whether to ask for the next page: when
    /// the end of the pages is within `leadScreens` of the lower edge of any of them. Nothing
    /// is asked for while the screen's height is not known.
    public func drawn(onScreensAt tops: [CGFloat], height: CGFloat) -> Drawn {
        var drawn = Drawn()
        drawn.pages = pages(onScreensAt: tops, height: height)
        let reach = max(height, 0) * (1 + Self.leadScreens)
        drawn.asksForMore = height > 0 && tops.contains { $0 + reach >= self.height }
        return drawn
    }

    /// The first index of `0..<count` for which `holds` is true, or `count`: `holds` is false
    /// for every index before it and true from it on.
    private static func firstIndex(in count: Int, where holds: (Int) -> Bool) -> Int {
        var low = 0
        var high = count
        while low < high {
            let middle = (low + high) / 2
            if holds(middle) {
                high = middle
            } else {
                low = middle + 1
            }
        }
        return low
    }

    static func rows(_ entries: Int, columns: Int) -> Int {
        (entries + columns - 1) / max(columns, 1)
    }
}
