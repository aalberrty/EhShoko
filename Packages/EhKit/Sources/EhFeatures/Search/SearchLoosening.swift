import EhModels

/// A way to loosen a search that found nothing, offered on the empty result. No counts are
/// shown: each would be another search.
nonisolated public enum SearchLoosening: Hashable, Sendable {
    /// "Drop the ★ 4+ minimum": the minimum rating the filter applies.
    case dropMinimumRating(Int)
    /// "Include all 10 categories": the filter shows fewer.
    case includeAllCategories
    /// "Search without artist: glacier works": the last tag of the keyword.
    case dropTag(SearchToken)

    /// Up to three ways to loosen a search for `keyword` under `filter`, in this order: the
    /// minimum rating, the categories, the last tag. Only what narrows the search is offered.
    public static func actions(for keyword: String, filter: Filter) -> [SearchLoosening] {
        let summary = FilterSummary(filter)
        var actions = [SearchLoosening]()
        if let rating = summary.minimumRating {
            actions.append(.dropMinimumRating(rating))
        }
        if summary.categoriesShown < FilterSummary.categoryCount {
            actions.append(.includeAllCategories)
        }
        if let tag = SearchTokens.split(keyword).tokens.last {
            actions.append(.dropTag(tag))
        }
        return actions
    }

    /// The keyword and filter to search again with.
    public func applied(to keyword: String, filter: Filter) -> (keyword: String, filter: Filter) {
        var keyword = keyword
        var filter = filter
        switch self {
        case .dropMinimumRating:
            filter.minRatingActivated = false
        case .includeAllCategories:
            filter.doujinshi = false
            filter.manga = false
            filter.artistCG = false
            filter.gameCG = false
            filter.western = false
            filter.nonH = false
            filter.imageSet = false
            filter.cosplay = false
            filter.asianPorn = false
            filter.misc = false
        case .dropTag(let tag):
            var split = SearchTokens.split(keyword)
            if let index = split.tokens.lastIndex(of: tag) {
                split.tokens.remove(at: index)
                keyword = split.keyword
            }
        }
        return (keyword, filter)
    }
}
