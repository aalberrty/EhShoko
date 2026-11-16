import EhModels

nonisolated extension SearchScope {
    /// The filter set a search in this scope uses, which the Filters button opens: the
    /// search's own for Everywhere, Watched's for Watched. Favourites have none, as their list
    /// has none.
    public var filterRange: FilterRange? {
        switch self {
        case .everywhere: .search
        case .watched: .watched
        case .favorites: nil
        }
    }
}
