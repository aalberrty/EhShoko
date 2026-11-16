import EhCore
import EhFeatures
import EhModels
import Foundation

/// The words a list's rows make from numbers and keys, for every list design: page counts,
/// ages, category names and tag texts, each made the first time a row asks and looked up after
/// that, so a row's body formats nothing (`spikes/S1.md`, rule 3; `Design/designs/README.md`
/// section 9.1). An entry carries its ages as a count and a unit and its page count as a
/// number; these turn into "2h ago", "added 2d ago", "48 p" once per value.
///
/// Each list view holds one, through its design's own table of words, colours and fonts, so it
/// goes away with the list. A plain class: filling it while the list builds rows invalidates
/// nothing.
final class ListRowWords {
    private var pageTexts: [Int: String] = [:]
    private var shortPageTexts: [Int: String] = [:]
    private var shortAges: [GalleryEntry.Age: String] = [:]
    private var agos: [GalleryEntry.Age: String] = [:]
    private var openedAges: [GalleryEntry.Age: String] = [:]
    private var addedAges: [GalleryEntry.Age: String] = [:]
    private var categoryNames: [EhModels.Category: String] = [:]
    private var tagTexts: [String: String] = [:]

    private lazy var shortAgeFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 1
        return formatter
    }()

    private lazy var relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.dateTimeStyle = .numeric
        return formatter
    }()

    /// The tag translations, while tags are translated; `nil` shows the site's text. Setting
    /// another table forgets the texts made from the last one.
    private(set) var translations: TagTranslationService?
    private var translationCount = 0

    /// Takes the translations table and how many entries it has, which changes when it loads.
    func useTranslations(_ table: TagTranslationService?, count: Int) {
        guard table !== translations || count != translationCount else { return }
        translations = table
        translationCount = count
        tagTexts.removeAll()
    }

    /// "48 pages".
    func pages(_ count: Int) -> String {
        Self.memo(&pageTexts, count) { L10n.Localizable.List.pages(count) }
    }

    /// "48 p".
    func shortPages(_ count: Int) -> String {
        Self.memo(&shortPageTexts, count) { L10n.Localizable.List.Pages.short(count) }
    }

    /// "2h": how long ago, in the fewest letters.
    func shortAge(_ age: GalleryEntry.Age) -> String {
        Self.memo(&shortAges, age) { shortAgeFormatter.string(from: age.dateComponents) ?? "" }
    }

    /// "2h ago".
    func ago(_ age: GalleryEntry.Age) -> String {
        Self.memo(&agos, age) { relativeFormatter.localizedString(from: Self.past(age)) }
    }

    /// "opened 2h ago": when History's gallery was last opened.
    func opened(_ age: GalleryEntry.Age) -> String {
        Self.memo(&openedAges, age) { L10n.Localizable.List.opened(ago(age)) }
    }

    /// "added 2d ago": when a favourite was favourited.
    func added(_ age: GalleryEntry.Age) -> String {
        Self.memo(&addedAges, age) { L10n.Localizable.List.added(ago(age)) }
    }

    /// "Doujinshi".
    func categoryName(_ category: EhModels.Category) -> String {
        Self.memo(&categoryNames, category) { category.localizedName }
    }

    /// The tag's text, translated while the translations are in use and the table has it,
    /// without emoji.
    func tagText(_ tag: GalleryEntry.Tag) -> String {
        guard let translations else { return tag.text }
        return Self.memo(&tagTexts, tag.id) {
            // What `GalleryTag.Content.chipText(translation:showsImages:)` gives without images.
            guard let value = translations.display(forKey: tag.id)?.displayValue, !value.isEmpty else {
                return tag.text
            }
            return value.removingEmojiPresentation
        }
    }

    /// The age as components counting back from now, which the relative formatter words as
    /// "… ago".
    private static func past(_ age: GalleryEntry.Age) -> DateComponents {
        switch age.unit {
        case .minute: DateComponents(minute: -age.count)
        case .hour: DateComponents(hour: -age.count)
        case .day: DateComponents(day: -age.count)
        case .week: DateComponents(weekOfMonth: -age.count)
        case .month: DateComponents(month: -age.count)
        case .year: DateComponents(year: -age.count)
        }
    }

    private static func memo<Key: Hashable>(_ table: inout [Key: String], _ key: Key, make: () -> String) -> String {
        if let text = table[key] { return text }
        let text = make()
        table[key] = text
        return text
    }
}
