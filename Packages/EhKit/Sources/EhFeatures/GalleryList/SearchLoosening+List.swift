import EhCore
import EhModels

/// What an empty search's list does after a way to loosen it was chosen.
public nonisolated enum LooseningStep: Equatable, Sendable {
    /// The Search filter was loosened: the same search loads again.
    case reload
    /// A new search for this keyword, with a tag dropped.
    case search(String)
}

extension SearchLoosening {
    /// Loosens the search for `keyword` (`ledger.md` section 3, the empty search): dropping the
    /// minimum rating or including every category changes the Search filter in `filterStore`,
    /// after which the list loads again; dropping a tag searches again without it, as a search
    /// of its own.
    @MainActor
    public func perform(on keyword: String, filterStore: FilterStore) -> LooseningStep {
        let loosened = applied(to: keyword, filter: filterStore[.search])
        switch self {
        case .dropMinimumRating, .includeAllCategories:
            filterStore[.search] = loosened.filter
            return .reload
        case .dropTag:
            return .search(loosened.keyword)
        }
    }
}
