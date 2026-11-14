import Foundation

/// What a `Filter` actually narrows, for the one-line summaries the lists show
/// ("8 of 10 · ★ 3+").
///
/// It describes the filter as the site receives it (see `FilterQuery` in `EhNetworking`):
/// excluding every category is no category filter, and the minimum rating, the page range and
/// the other advanced options count only while advanced search is on.
public struct FilterSummary: Sendable, Hashable {
    /// The number of categories in the filter.
    public static let categoryCount = 10

    /// How many of the ten categories are shown.
    public let categoriesShown: Int
    /// The minimum rating (2–5), or `nil` for none.
    public let minimumRating: Int?
    /// The smallest page count asked for, or `nil` for no lower bound.
    public let minimumPages: Int?
    /// The largest page count asked for, or `nil` for no upper bound.
    public let maximumPages: Int?
    /// How many of the other advanced options differ from their defaults.
    public let advancedOptionCount: Int

    public init(_ filter: Filter) {
        let excluded = Self.categoryFlags(filter).filter { $0 }.count
        // Excluding every category means no category filter, as on the site.
        categoriesShown = excluded == Self.categoryCount ? Self.categoryCount : Self.categoryCount - excluded

        guard filter.advanced else {
            minimumRating = nil
            minimumPages = nil
            maximumPages = nil
            advancedOptionCount = 0
            return
        }
        minimumRating = filter.minRatingActivated && (2...5).contains(filter.minRating) ? filter.minRating : nil
        (minimumPages, maximumPages) = filter.pageRangeActivated ? Self.pageRange(filter) : (nil, nil)
        let defaults = Self.advancedFlags(Filter())
        advancedOptionCount = zip(Self.advancedFlags(filter), defaults).filter { $0 != $1 }.count
    }

    /// Whether the filter narrows nothing: what the site shows without one.
    public var isDefault: Bool {
        categoriesShown == Self.categoryCount && minimumRating == nil
            && minimumPages == nil && maximumPages == nil && advancedOptionCount == 0
    }

    private static func categoryFlags(_ filter: Filter) -> [Bool] {
        [
            filter.doujinshi, filter.manga, filter.artistCG, filter.gameCG, filter.western,
            filter.nonH, filter.imageSet, filter.cosplay, filter.asianPorn, filter.misc
        ]
    }

    private static func advancedFlags(_ filter: Filter) -> [Bool] {
        [
            filter.galleryName, filter.galleryTags, filter.galleryDesc, filter.torrentFilenames,
            filter.onlyWithTorrents, filter.lowPowerTags, filter.downvotedTags, filter.expungedGalleries,
            filter.disableLanguage, filter.disableUploader, filter.disableTags
        ]
    }

    /// The bounds the site receives: both only when they form a valid range, a single bound
    /// when it is positive.
    private static func pageRange(_ filter: Filter) -> (Int?, Int?) {
        switch (Int(filter.pageLowerBound), Int(filter.pageUpperBound)) {
        case let (.some(lower), .some(upper)):
            lower > 0 && upper > 0 && lower <= upper ? (lower, upper) : (nil, nil)
        case let (.some(lower), .none):
            (lower > 0 ? lower : nil, nil)
        case let (.none, .some(upper)):
            (nil, upper > 0 ? upper : nil)
        case (.none, .none):
            (nil, nil)
        }
    }
}
