/// A Toplists gallery with its rank.
public nonisolated struct RankedEntry: Identifiable, Equatable, Sendable {
    public let entry: GalleryEntry
    /// 1-based; `nil` while Find narrows the list, when a gallery's rank is not known.
    public let rank: Int?

    public var id: String { entry.id }

    public init(entry: GalleryEntry, rank: Int?) {
        self.entry = entry
        self.rank = rank
    }
}

/// Toplists' galleries by the page they came from, for every list design: the first page's,
/// then each later page with its number for the "Page 2" divider. Ranks count from the page's
/// number, so a list opened at page 5 starts at 201.
///
/// Worked out from the entries and the page starts when they change, never while the list
/// scrolls.
public nonisolated struct RankedPages: Sendable {
    public struct Page: Identifiable, Sendable {
        public let number: Int
        /// Its place among the list's loaded pages, the first page being 0: the index
        /// `sections` and `ListPageSpans` know it by.
        public let index: Int
        public let rows: ArraySlice<RankedEntry>

        public var id: Int { number }
    }

    public let first: ArraySlice<RankedEntry>
    public let later: [Page]

    /// The site's Toplists show 50 galleries a page.
    public static let sitePageSize = 50

    /// How many galleries each section holds, in order: the first page's, then each later
    /// page's.
    public var sections: [Int] {
        [first.count] + later.map(\.rows.count)
    }

    /// - Parameters:
    ///   - pageStarts: where each loaded page starts in `entries`; empty for a list of one
    ///     page (Popular) and while Find narrows it.
    ///   - findText: what Find narrows the list by; while it does, no rank is known.
    public init(entries: [GalleryEntry], pageStarts: [PageStart], findText: String) {
        guard !pageStarts.isEmpty else {
            let ranks = findText.isEmpty
            first = entries.enumerated().map { RankedEntry(entry: $1, rank: ranks ? $0 + 1 : nil) }[...]
            later = []
            return
        }
        let pageSize = Self.pageSize(of: pageStarts)
        var rows: [RankedEntry] = []
        rows.reserveCapacity(entries.count)
        // Where each page's galleries are in `rows`.
        var bounds: [(number: Int, range: Range<Int>)] = []
        for (offset, page) in pageStarts.enumerated() {
            let end = offset + 1 < pageStarts.count ? pageStarts[offset + 1].index : entries.count
            let lower = min(page.index, entries.count)
            let base = Self.firstRank(ofPage: page.page, pageSize: pageSize)
            let rowsStart = rows.count
            for index in lower..<max(min(end, entries.count), lower) {
                rows.append(RankedEntry(entry: entries[index], rank: base + index - lower))
            }
            bounds.append((page.page, rowsStart..<rows.count))
        }
        first = rows[bounds.first?.range ?? 0..<0]
        later = bounds.enumerated().dropFirst().map {
            Page(number: $0.element.number, index: $0.offset, rows: rows[$0.element.range])
        }
    }

    /// The galleries a page holds: as far apart as the first two loaded pages start, or the
    /// site's 50 while only one is loaded.
    public static func pageSize(of pageStarts: [PageStart]) -> Int {
        guard pageStarts.count > 1 else { return sitePageSize }
        let size = pageStarts[1].index - pageStarts[0].index
        return size > 0 ? size : sitePageSize
    }

    /// The rank of the first gallery of `page` (1-based).
    public static func firstRank(ofPage page: Int, pageSize: Int) -> Int {
        (page - 1) * pageSize + 1
    }
}
