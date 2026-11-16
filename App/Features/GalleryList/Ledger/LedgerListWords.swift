import EhFeatures
import EhModels
import SwiftUI

/// The words a Ledger list shows, looked up instead of formatted while it scrolls
/// (`ledger.md` section 3): each row's line of facts, kept until the values in it change, and
/// the day headings. The words in a line ("2h ago", "added 2d ago", "48 p") are the ones every
/// list makes once per value (`ListRowWords`).
///
/// One per list screen, held as `@State` of `LedgerListView`, so it goes with the screen and
/// no other design pays for it. It is a plain class: filling it while the list builds rows
/// invalidates nothing.
final class LedgerListWords {
    /// Which age a row's line ends with.
    nonisolated enum AgeKind: Hashable {
        /// "2h ago": when the gallery was posted.
        case posted
        /// "added 2d ago": favourites, when it was favourited.
        case added
        /// "opened 2h ago": History, when it was last opened.
        case opened
    }

    nonisolated private struct AgeKey: Hashable {
        let age: GalleryEntry.Age
        let kind: AgeKind
    }

    /// Everything a line of facts is made of, to tell when a stored line is out of date.
    nonisolated private struct FactsKey: Equatable {
        let category: Category
        let language: String?
        let pages: Int
        let rating: String
        let age: AgeKey
        let rank: Int?
    }

    private let words = ListRowWords()
    private var facts: [String: (key: FactsKey, line: AttributedString)] = [:]
    private var dayTitles: [Date: String] = [:]
    /// The day "Today" meant when `dayTitles` was filled.
    private var today: Date?

    private lazy var dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEEEdMMMM")
        return formatter
    }()

    private lazy var dayInOtherYearFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEEEdMMMMy")
        return formatter
    }()

    /// The line under a row's title: the category in its colour, the language, "48 p",
    /// "★ 4.72" and the age, after "No. 4" in a ranked list. The language is left out when
    /// neither the tags nor the title name one.
    func facts(for entry: GalleryEntry, ending kind: AgeKind, rank: Int?) -> AttributedString {
        let gallery = entry.gallery
        let age: AgeKey = switch kind {
        case .added: entry.addedAge.map { AgeKey(age: $0, kind: .added) } ?? AgeKey(age: entry.postedAge, kind: .posted)
        case .opened: entry.openedAge.map { AgeKey(age: $0, kind: .opened) } ?? AgeKey(age: entry.postedAge, kind: .posted)
        case .posted: AgeKey(age: entry.postedAge, kind: .posted)
        }
        let key = FactsKey(
            category: gallery.category, language: entry.languageCode, pages: gallery.pageCount,
            rating: entry.ratingText, age: age, rank: rank
        )
        if let stored = facts[entry.id], stored.key == key { return stored.line }
        let line = makeFacts(key)
        facts[entry.id] = (key, line)
        return line
    }

    /// "Today", "Yesterday", then the date: "Thursday, 12 November", with the year when it is
    /// not this year's.
    func dayTitle(for day: Date, calendar: Calendar) -> String {
        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)
        if today != startOfToday {
            // Past midnight the words of every day change.
            dayTitles.removeAll(keepingCapacity: true)
            today = startOfToday
        }
        if let title = dayTitles[day] { return title }
        let title: String
        if day == startOfToday {
            title = L10n.Localizable.List.Day.today
        } else if let yesterday = calendar.date(byAdding: .day, value: -1, to: startOfToday), day == yesterday {
            title = L10n.Localizable.List.Day.yesterday
        } else {
            let sameYear = calendar.isDate(day, equalTo: now, toGranularity: .year)
            let formatter = sameYear ? dayFormatter : dayInOtherYearFormatter
            formatter.calendar = calendar
            formatter.timeZone = calendar.timeZone
            title = formatter.string(from: day)
        }
        dayTitles[day] = title
        return title
    }

    private func makeFacts(_ key: FactsKey) -> AttributedString {
        var parts: [String] = []
        if let rank = key.rank {
            parts.append(L10n.Localizable.List.rank(rank))
        }
        var name = AttributedString(words.categoryName(key.category))
        name.swiftUI.foregroundColor = key.category.markColor
        name.swiftUI.font = LedgerGalleryRow.factsEmphasisFont
        var rest = [String]()
        if let language = key.language {
            rest.append(language)
        }
        rest.append(words.shortPages(key.pages))
        rest.append("★ " + key.rating)
        rest.append(ageText(key.age))
        let separator = " · "
        var line = AttributedString(parts.isEmpty ? "" : parts.joined(separator: separator) + separator)
        line.append(name)
        line.append(AttributedString(separator + rest.joined(separator: separator)))
        return line
    }

    private func ageText(_ key: AgeKey) -> String {
        switch key.kind {
        case .posted: words.ago(key.age)
        case .added: words.added(key.age)
        case .opened: words.opened(key.age)
        }
    }
}
