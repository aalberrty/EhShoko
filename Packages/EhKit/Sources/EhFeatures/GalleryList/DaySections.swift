import EhModels
import Foundation

/// Where each day starts in a list ordered by date, for Ledger's day headings: lists in posted
/// order (Front Page, Watched, search) and History (by the day each gallery was opened).
///
/// Only boundaries are kept, never the entries. A list that grew by a page is extended from
/// where it ended, so the cost of a page is the cost of its own rows. The view that draws the
/// headings owns the value (`@State`): no other design pays for it.
public nonisolated struct DaySections: Equatable, Sendable {
    /// Which date of a gallery orders the list.
    public enum Order: Sendable {
        /// `postedDate`.
        case posted
        /// `lastOpenDate` (History).
        case opened

        func date(of gallery: Gallery) -> Date {
            switch self {
            case .posted: gallery.postedDate
            case .opened: gallery.lastOpenDate ?? gallery.postedDate
            }
        }
    }

    /// One day's run of rows.
    public struct Section: Identifiable, Equatable, Sendable {
        /// The start of the day, in the calendar the sections were made with.
        public let day: Date
        /// The rows of the day, as indices into the list.
        public internal(set) var rows: Range<Int>

        public var id: Int { rows.lowerBound }
    }

    public private(set) var sections: [Section] = []
    /// The first and last entry seen, to tell an appended page from a replaced list.
    private var firstID: String?
    private var lastID: String?
    private var calendar: Calendar?
    private var order: Order?

    public init() {}

    /// The sections of `dates`, in list order: a new one starts wherever the day differs
    /// from the row before.
    public static func group(_ dates: some Sequence<Date>, calendar: Calendar) -> DaySections {
        var sections = DaySections()
        sections.calendar = calendar
        sections.append(dates, calendar: calendar)
        return sections
    }

    /// The number of rows grouped.
    public var count: Int { sections.last?.rows.upperBound ?? 0 }

    /// Groups `dates` as the rows after the ones already grouped.
    public mutating func append(_ dates: some Sequence<Date>, calendar: Calendar) {
        var index = count
        for date in dates {
            let day = calendar.startOfDay(for: date)
            if let last = sections.indices.last, sections[last].day == day {
                sections[last].rows = sections[last].rows.lowerBound..<(index + 1)
            } else {
                sections.append(Section(day: day, rows: index..<(index + 1)))
            }
            index += 1
        }
    }

    /// Brings the sections up to date with `entries`: extends them when the list only grew at
    /// its end (a page appended), and groups the whole list again when it was replaced, or when
    /// the order or the calendar (its time zone) changed.
    public mutating func update(with entries: [GalleryEntry], by order: Order, calendar: Calendar) {
        let grew = self.calendar == calendar && self.order == order && entries.count >= count && count > 0
            && entries.first?.id == firstID && entries[count - 1].id == lastID
        if grew {
            append(entries[count...].lazy.map { order.date(of: $0.gallery) }, calendar: calendar)
        } else {
            self = Self.group(entries.lazy.map { order.date(of: $0.gallery) }, calendar: calendar)
        }
        self.order = order
        firstID = entries.first?.id
        lastID = entries.last?.id
    }
}
