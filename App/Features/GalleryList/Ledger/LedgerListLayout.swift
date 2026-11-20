import EhFeatures
import EhModels
import Foundation

/// How a Ledger list is cut into runs under small-capitals headings (`ledger.md` section 3).
nonisolated enum LedgerGrouping: Equatable {
    /// One run, no headings: Popular, the favourites, a search within them.
    case none
    /// A heading starts each day: lists in posted order (Front Page, Watched, search results)
    /// and History, by the day each gallery was opened.
    case days(DaySections.Order)
    /// A heading starts each page and rows carry their rank: Toplists.
    case pages
}

/// One run of rows under its heading.
nonisolated struct LedgerSection: Identifiable, Equatable {
    /// The run's first row, which stays where it is when a page is appended.
    let id: Int
    let title: String
    /// The rows, as indices into the list's entries.
    let rows: Range<Int>
    /// Toplists: the rank of the run's first row.
    let firstRank: Int?
}

/// Where a Ledger list's headings go, and where each entry is: worked out when the entries
/// change, never while the list scrolls.
///
/// Held as `@State` of `LedgerListView`, a plain class, so asking it while the list builds
/// rows invalidates nothing. A list that grew by a page is extended from where it ended
/// (`DaySections` keeps only boundaries), so a page costs what its own rows cost.
final class LedgerListLayout {
    private struct Key: Equatable {
        let count: Int
        let firstID: String?
        let lastID: String?
        let grouping: LedgerGrouping
        let pageStarts: [PageStart]
        let calendar: Calendar
    }

    /// The runs, which cover every entry in order; empty for a list drawn as one run.
    private(set) var sections: [LedgerSection] = []
    private var key: Key?
    private var days = DaySections()
    private var indexByID: [String: Int] = [:]

    /// The index of the entry with `id` in the entries last given to `update`.
    func index(of id: String) -> Int? {
        indexByID[id]
    }

    /// Brings the layout up to date with `entries`. Cheap when nothing changed: a comparison
    /// of the ends of the list and its page starts. Returns whether the list was replaced
    /// rather than unchanged or grown by a page.
    @discardableResult
    func update(
        _ entries: [GalleryEntry], grouping: LedgerGrouping, pageStarts: [PageStart], words: LedgerListWords,
        calendar: Calendar = .autoupdatingCurrent
    ) -> Bool {
        let next = Key(
            count: entries.count, firstID: entries.first?.id, lastID: entries.last?.id, grouping: grouping,
            pageStarts: grouping == .pages ? pageStarts : [], calendar: calendar
        )
        guard next != key else { return false }
        let grew = key.map { old in
            old.grouping == next.grouping && old.calendar == next.calendar && old.count > 0
                && old.count <= next.count && old.firstID == next.firstID && entries[old.count - 1].id == old.lastID
        } ?? false
        updateIndex(entries, from: grew ? (key?.count ?? 0) : 0)
        key = next
        switch grouping {
        case .none:
            sections = []
        case .days(let order):
            days.update(with: entries, by: order, calendar: calendar)
            sections = days.sections.map { section in
                LedgerSection(
                    id: section.rows.lowerBound, title: words.dayTitle(for: section.day, calendar: calendar),
                    rows: section.rows, firstRank: nil
                )
            }
        case .pages:
            sections = Self.pageSections(pageStarts, count: entries.count)
        }
        // Runs that leave a row out would hide it: draw the list as one run instead.
        if sections.first?.rows.lowerBound != 0 || sections.last?.rows.upperBound != entries.count
            || zip(sections, sections.dropFirst()).contains(where: { $0.rows.upperBound != $1.rows.lowerBound }) {
            sections = []
        }
        return !grew
    }

    private func updateIndex(_ entries: [GalleryEntry], from start: Int) {
        if start == 0 {
            indexByID.removeAll(keepingCapacity: true)
        }
        indexByID.reserveCapacity(entries.count)
        for index in start..<entries.count {
            indexByID[entries[index].id] = index
        }
    }

    /// One run per loaded page, headed "Page n". Without page starts (a narrowed list) there
    /// are no runs and no ranks.
    static func pageSections(_ starts: [PageStart], count: Int) -> [LedgerSection] {
        let pageSize = RankedPages.pageSize(of: starts)
        return starts.enumerated().compactMap { offset, start in
            let end = offset + 1 < starts.count ? starts[offset + 1].index : count
            guard start.index < end, end <= count else { return nil }
            return LedgerSection(
                id: start.page, title: L10n.Localizable.List.Page.divider(start.page), rows: start.index..<end,
                firstRank: RankedPages.firstRank(ofPage: start.page, pageSize: pageSize)
            )
        }
    }
}
