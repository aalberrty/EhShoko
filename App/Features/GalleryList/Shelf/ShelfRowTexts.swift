import EhCore
import EhFeatures
import EhModels
import SwiftUI
import UIKit

/// The words, colours and images Shelf's rows look up, so that a row's body formats nothing
/// (`spikes/S1.md`, rule 3): the words every list makes from numbers (`ListRowWords`: one
/// string per age, per page count and per tag, made the first time a row asks); the category
/// colours, the folder names and the star strips, made once.
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

    private let words = ListRowWords()
    private var starStrips: [Image] = []
    private lazy var categories: [EhModels.Category: CategoryText] = Dictionary(
        uniqueKeysWithValues: EhModels.Category.allCases.map { [words] category in
            let color = category.markColor
            return (category, CategoryText(name: words.categoryName(category), color: color, tint: color.opacity(0.17)))
        }
    )

    var look: Look { inputs?.look ?? .shelf }
    /// The title in the look's face: New York under Ledger.
    private(set) var titleFont = ShelfRowFonts.title(.default)
    var tint: Color { inputs?.tint ?? .accentColor }

    /// Takes the current inputs; when they differ from the last ones, forgets what depended on
    /// them and moves `revision`. Called from the list view's body, before rows are made.
    func prepare(_ next: Inputs) {
        guard next != inputs else { return }
        let old = inputs
        inputs = next
        revision += 1
        if old?.look != next.look {
            titleFont = ShelfRowFonts.title(next.look.titleDesign)
        }
        if old?.typeSize != next.typeSize {
            metrics = ShelfRowMetrics(typeSize: next.typeSize)
            starStrips = []
        }
        words.useTranslations(next.translations, count: next.translationCount)
    }

    // MARK: Lookups

    func category(_ category: EhModels.Category) -> CategoryText {
        categories[category] ?? CategoryText(name: "", color: .gray, tint: .clear)
    }

    /// "48 pages".
    func pages(_ count: Int) -> String {
        words.pages(count)
    }

    /// "2h": how long ago the gallery was posted.
    func posted(_ age: GalleryEntry.Age) -> String {
        words.shortAge(age)
    }

    /// "opened 2h ago".
    func opened(_ age: GalleryEntry.Age) -> String {
        words.opened(age)
    }

    /// "Top Shelf · added 2d ago", or the folder's name alone when the date is not known.
    func favoriteLine(favorite: FavoriteMark, added age: GalleryEntry.Age?) -> String {
        let names = inputs?.folderNames ?? []
        let name = names.indices.contains(favorite.folder) ? names[favorite.folder] : ""
        guard let age else { return name }
        let addedText = words.added(age)
        return name.isEmpty ? addedText : name + " · " + addedText
    }

    /// The tag's text, translated when the setting is on and the table has it, without emoji.
    func tagText(_ tag: GalleryEntry.Tag) -> String {
        words.tagText(tag)
    }

    /// Five stars for a rating of `halfStars` (0...10) as one template image, drawn once per
    /// text size: one image in the row instead of five symbols.
    func stars(halfStars: Int) -> Image {
        if starStrips.isEmpty {
            starStrips = ShelfRowStars.strips(pointSize: metrics.starPointSize)
        }
        return starStrips[min(max(halfStars, 0), starStrips.count - 1)]
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
        // Held at the largest standard size: at accessibility sizes five stars would take the
        // line and leave no room for the rating they stand for.
        starPointSize = min(caption2.scaledValue(for: 11, compatibleWith: traits), 15)
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
