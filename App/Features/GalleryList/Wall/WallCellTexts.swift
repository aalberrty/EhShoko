import EhCore
import EhFeatures
import EhModels
import SwiftUI
import UIKit

/// The words, colours and fonts Wall's cells look up, so that a cell's body formats nothing
/// (`spikes/S1.md`, rule 3): the words every list makes from numbers (`ListRowWords`: one
/// string per page count, per age and per tag, made the first time a cell asks); the category
/// colours and tiles and the caption's fonts, made once.
///
/// Owned by `WallListView` as `@State` and handed to cells in their style, so it goes away
/// with the list. Nothing observes it: when what it was made from changes, the list view calls
/// `prepare`, which clears what depended on it and moves `revision`, and the cells' style
/// changes with it.
final class WallCellTexts {
    /// What the strings and colours depend on besides the entries.
    struct Inputs: Equatable {
        var look: Look
        var tint: Color
        var typeSize: DynamicTypeSize
        /// The translations table when tags are translated, else `nil`.
        var translations: TagTranslationService?
        /// Changes when the table does.
        var translationCount: Int

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.look == rhs.look && lhs.tint == rhs.tint && lhs.typeSize == rhs.typeSize
                && lhs.translations === rhs.translations && lhs.translationCount == rhs.translationCount
        }
    }

    struct CategoryText {
        let name: String
        let color: Color
        /// The cover's tile while its image is on the way: the look's surface with 26% of the
        /// category's colour.
        let tile: Color
    }

    private(set) var revision = 0
    private(set) var inputs: Inputs?
    private(set) var metrics = WallCellMetrics(typeSize: .large)
    /// Large's title, in the look's face: New York under Ledger.
    private(set) var largeTitleFont = WallCellFonts.largeTitle(.default)
    private(set) var mediumTitleFont = WallCellFonts.mediumTitle(.default)

    private let words = ListRowWords()
    private var categories: [EhModels.Category: CategoryText] = [:]

    var look: Look { inputs?.look ?? .wall }
    var tint: Color { inputs?.tint ?? .accentColor }
    /// "Cover not saved", under a cover that could not be loaded.
    let coverMissing = L10n.Localizable.List.Cover.missing

    /// Takes the current inputs; when they differ from the last ones, forgets what depended on
    /// them and moves `revision`. Called from the list view's body, before cells are made.
    func prepare(_ next: Inputs) {
        guard next != inputs else { return }
        let old = inputs
        inputs = next
        revision += 1
        if old?.look != next.look {
            largeTitleFont = WallCellFonts.largeTitle(next.look.titleDesign)
            mediumTitleFont = WallCellFonts.mediumTitle(next.look.titleDesign)
            categories = [:]
        }
        if old?.typeSize != next.typeSize {
            metrics = WallCellMetrics(typeSize: next.typeSize)
        }
        words.useTranslations(next.translations, count: next.translationCount)
    }

    // MARK: Lookups

    func category(_ category: EhModels.Category) -> CategoryText {
        if let text = categories[category] { return text }
        let color = category.markColor
        let text = CategoryText(
            name: words.categoryName(category), color: color, tile: look.surface.mix(with: color, by: 0.26)
        )
        categories[category] = text
        return text
    }

    /// "48 pages", in Large's caption.
    func pages(_ count: Int) -> String {
        words.pages(count)
    }

    /// "48 p", in Medium's.
    func shortPages(_ count: Int) -> String {
        words.shortPages(count)
    }

    /// "opened 2h ago": History's caption.
    func opened(_ age: GalleryEntry.Age) -> String {
        words.opened(age)
    }

    /// The tag's text, translated when the setting is on and the table has it, without emoji.
    func tagText(_ tag: GalleryEntry.Tag) -> String {
        words.tagText(tag)
    }
}

/// The type of a cell's caption (`wall.md` section 3). Fixed text styles, so a cell creates no
/// font; the titles' face is the look's (`WallCellTexts`).
nonisolated enum WallCellFonts {
    static func largeTitle(_ design: Font.Design) -> Font {
        .system(.subheadline, design: design, weight: .semibold)
    }
    static func mediumTitle(_ design: Font.Design) -> Font {
        .system(.caption, design: design, weight: .semibold)
    }
    static let credit = Font.caption
    static let largeFacts = Font.caption
    static let mediumFacts = Font.caption2
    static let tag = Font.caption2
}

/// The caption's fixed spacing, and its heights at one text size: every cell of a density has
/// one height, so the grid measures no text and a row's place is arithmetic.
struct WallCellMetrics: Equatable {
    /// Between the cover and the caption.
    static let mediumTop: CGFloat = 5
    static let largeTop: CGFloat = 7
    static let mediumLineSpacing: CGFloat = 1
    static let creditSpacing: CGFloat = 2
    static let factsSpacing: CGFloat = 5
    static let tagSpacing: CGFloat = 5
    static let dotSize: CGFloat = 7
    static let coverRadius: CGFloat = 8

    /// Medium's caption: the title on one line and the facts.
    let medium: CGFloat
    /// Large's: the title on two lines, the credit and the facts; without and with the tags.
    let large: (plain: CGFloat, tags: CGFloat)
    let chipHeight: CGFloat
    /// About what one tag chip takes on the line, with the space after it: for how many fit.
    let chipWidth: CGFloat
    /// "Page 2" between the pages of a numbered list.
    let dividerHeight: CGFloat

    init(typeSize: DynamicTypeSize) {
        let traits = UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(typeSize))
        func line(_ style: UIFont.TextStyle) -> CGFloat {
            UIFont.preferredFont(forTextStyle: style, compatibleWith: traits).lineHeight.rounded(.up)
        }
        medium = Self.mediumTop + line(.caption1) + Self.mediumLineSpacing + line(.caption2)
        let plain = Self.largeTop + line(.subheadline) * 2 + Self.creditSpacing + line(.caption1)
            + Self.factsSpacing + line(.caption1)
        chipHeight = max(19, line(.caption2) + 4)
        large = (plain, plain + Self.tagSpacing + chipHeight)
        chipWidth = UIFontMetrics(forTextStyle: .caption2).scaledValue(for: 62, compatibleWith: traits)
        dividerHeight = line(.footnote) + 24
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.medium == rhs.medium && lhs.large == rhs.large && lhs.chipHeight == rhs.chipHeight
            && lhs.chipWidth == rhs.chipWidth && lhs.dividerHeight == rhs.dividerHeight
    }

    /// The caption's height at `density`; Small has none.
    func captionHeight(for density: WallDensity, showsTags: Bool) -> CGFloat {
        switch density {
        case .large: showsTags ? large.tags : large.plain
        case .medium: medium
        case .small: 0
        }
    }
}
