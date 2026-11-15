import EhCore
import EhFeatures
import EhModels
import SwiftUI
import UIKit

/// The words, colours and images Shelf's rows look up, so that a row's body formats nothing
/// (`spikes/S1.md`, rule 3): one string per age and kind, per page count and per tag, made the
/// first time a row asks; the category names and colours, the folder names and the star strips,
/// made once.
///
/// Owned by `ShelfListView` as `@State` and handed to rows in their style, so it goes away
/// with the list. Nothing observes it: when what it was made from changes, the list view calls
/// `prepare`, which clears it and moves `revision`, and the rows' style changes with it.
final class ShelfRowTexts {
    /// What the strings depend on besides the entries.
    struct Inputs: Equatable {
        var look: Look
        var tint: Color
        var typeSize: DynamicTypeSize
        /// The translations table when tags are translated, else `nil`.
        var translations: TagTranslationService?
        /// Changes when the table does.
        var translationCount: Int
        /// The favourites folders' names, for a favourites list; empty elsewhere.
        var folderNames: [String]

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.look == rhs.look && lhs.tint == rhs.tint && lhs.typeSize == rhs.typeSize
                && lhs.translations === rhs.translations && lhs.translationCount == rhs.translationCount
                && lhs.folderNames == rhs.folderNames
        }
    }

    struct CategoryText {
        let name: String
        let color: Color
        /// The capsule behind the name: the colour at 17%.
        let tint: Color
    }

    private(set) var revision = 0
    private(set) var inputs: Inputs?
    private(set) var metrics = ShelfRowMetrics(typeSize: .large)

    private var posted: [GalleryEntry.Age: String] = [:]
    private var opened: [GalleryEntry.Age: String] = [:]
    private var added: [GalleryEntry.Age: String] = [:]
    private var pageCounts: [Int: String] = [:]
    private var tagTexts: [String: String] = [:]
    private var starStrips: [Image] = []
    private lazy var categories: [EhModels.Category: CategoryText] = Dictionary(
        uniqueKeysWithValues: EhModels.Category.allCases.map { category in
            let color = category.markColor
            return (category, CategoryText(name: category.localizedName, color: color, tint: color.opacity(0.17)))
        }
    )
    private lazy var shortAge: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 1
        return formatter
    }()
    private lazy var relativeAge: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.dateTimeStyle = .numeric
        return formatter
    }()

    var look: Look { inputs?.look ?? .shelf }
    var tint: Color { inputs?.tint ?? .accentColor }

    /// Takes the current inputs; when they differ from the last ones, forgets what depended on
    /// them and moves `revision`. Called from the list view's body, before rows are made.
    func prepare(_ next: Inputs) {
        guard next != inputs else { return }
        let old = inputs
        inputs = next
        revision += 1
        if old?.typeSize != next.typeSize {
            metrics = ShelfRowMetrics(typeSize: next.typeSize)
            starStrips = []
        }
        if old?.translations !== next.translations || old?.translationCount != next.translationCount {
            tagTexts = [:]
        }
    }

    // MARK: Lookups

    func category(_ category: EhModels.Category) -> CategoryText {
        categories[category] ?? CategoryText(name: "", color: .gray, tint: .clear)
    }

    /// "48 pages".
    func pages(_ count: Int) -> String {
        memo(&pageCounts, count) { L10n.Localizable.List.pages(count) }
    }

    /// "2h": how long ago the gallery was posted.
    func posted(_ age: GalleryEntry.Age) -> String {
        memo(&posted, age) { shortAge.string(from: age.dateComponents) ?? "" }
    }

    /// "opened 2h ago".
    func opened(_ age: GalleryEntry.Age) -> String {
        memo(&opened, age) { L10n.Localizable.List.opened(ago(age)) }
    }

    /// "Top Shelf · added 2d ago", or the folder's name alone when the date is not known.
    func favoriteLine(favorite: FavoriteMark, added age: GalleryEntry.Age?) -> String {
        let names = inputs?.folderNames ?? []
        let name = names.indices.contains(favorite.folder) ? names[favorite.folder] : ""
        guard let age else { return name }
        let addedText = memo(&added, age) { L10n.Localizable.List.added(ago(age)) }
        return name.isEmpty ? addedText : name + " · " + addedText
    }

    /// The tag's text, translated when the setting is on and the table has it, without emoji.
    func tagText(_ tag: GalleryEntry.Tag) -> String {
        guard let translations = inputs?.translations else { return tag.text }
        return memo(&tagTexts, tag.id) {
            // What `GalleryTag.Content.chipText(translation:showsImages:)` gives without images.
            guard let value = translations.display(forKey: tag.id)?.displayValue, !value.isEmpty else {
                return tag.text
            }
            return value.removingEmojiPresentation
        }
    }

    /// Five stars for a rating of `halfStars` (0...10) as one template image, drawn once per
    /// text size: one image in the row instead of five symbols.
    func stars(halfStars: Int) -> Image {
        if starStrips.isEmpty {
            starStrips = ShelfRowStars.strips(pointSize: metrics.starPointSize)
        }
        return starStrips[min(max(halfStars, 0), starStrips.count - 1)]
    }

    private func ago(_ age: GalleryEntry.Age) -> String {
        var components = age.dateComponents
        // Back in time: the formatter says "2h ago" for a negative interval.
        components.minute = components.minute.map { -$0 }
        components.hour = components.hour.map { -$0 }
        components.day = components.day.map { -$0 }
        components.weekOfMonth = components.weekOfMonth.map { -$0 }
        components.month = components.month.map { -$0 }
        components.year = components.year.map { -$0 }
        return relativeAge.localizedString(from: components)
    }

    private func memo<Key: Hashable>(_ table: inout [Key: String], _ key: Key, make: () -> String) -> String {
        if let text = table[key] { return text }
        let text = make()
        table[key] = text
        return text
    }
}

/// The row's fixed sizes, and its heights at one text size: the cover's, or the text column's
/// when that is taller (larger text, the tag line).
struct ShelfRowMetrics: Equatable {
    static let capsuleHeight: CGFloat = 20
    static let creditSpacing: CGFloat = 2
    static let capsuleSpacing: CGFloat = 6
    static let tagSpacing: CGFloat = 6
    static let footerSpacing: CGFloat = 7

    /// Without and with the tag line.
    let standard: (plain: CGFloat, tags: CGFloat)
    let ranked: CGFloat
    let starPointSize: CGFloat
    /// About what one tag chip takes on the line, with the space after it: for how many fit.
    let chipWidth: CGFloat

    init(typeSize: DynamicTypeSize) {
        let traits = UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(typeSize))
        func line(_ style: UIFont.TextStyle) -> CGFloat {
            UIFont.preferredFont(forTextStyle: style, compatibleWith: traits).lineHeight.rounded(.up)
        }
        let capsule = max(Self.capsuleHeight, line(.caption1) + 4)
        let chip = max(Self.capsuleHeight, line(.caption2) + 4)
        let text = line(.callout) * 2 + Self.creditSpacing + line(.footnote) + Self.capsuleSpacing + capsule
            + Self.footerSpacing + line(.caption1)
        standard = (
            max(ShelfGalleryRow.cover.height, text), max(ShelfGalleryRow.cover.height, text + Self.tagSpacing + chip)
        )
        ranked = max(ShelfGalleryRow.rankedCover.height, text)
        let caption2 = UIFontMetrics(forTextStyle: .caption2)
        starPointSize = caption2.scaledValue(for: 11, compatibleWith: traits)
        chipWidth = caption2.scaledValue(for: 56, compatibleWith: traits)
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.standard == rhs.standard && lhs.ranked == rhs.ranked && lhs.starPointSize == rhs.starPointSize
            && lhs.chipWidth == rhs.chipWidth
    }
}

/// The eleven strips of five stars, one per half-star rating, as template images.
enum ShelfRowStars {
    static func strips(pointSize: CGFloat) -> [Image] {
        let configuration = UIImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
        let symbols = ["star", "star.leadinghalf.filled", "star.fill"].map {
            UIImage(systemName: $0, withConfiguration: configuration)
        }
        let width = symbols.compactMap { $0?.size.width }.max() ?? pointSize
        let height = symbols.compactMap { $0?.size.height }.max() ?? pointSize
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width * 5, height: height))
        return (0...10).map { half in
            let strip = renderer.image { _ in
                for index in 0..<5 {
                    // 2 for a full star, 1 for half, 0 for none.
                    let fill = min(max(half - index * 2, 0), 2)
                    guard let symbol = symbols[fill] else { continue }
                    let origin = CGPoint(
                        x: CGFloat(index) * width + (width - symbol.size.width) / 2,
                        y: (height - symbol.size.height) / 2
                    )
                    symbol.withTintColor(.black).draw(at: origin)
                }
            }
            return Image(uiImage: strip.withRenderingMode(.alwaysTemplate))
        }
    }
}
