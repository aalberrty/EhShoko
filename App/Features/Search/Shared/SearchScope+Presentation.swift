import EhFeatures
import EhModels

extension SearchScope {
    /// The scope's name, as the scope menu and Shelf's segmented control show it.
    var localizedName: String {
        switch self {
        case .everywhere: L10n.Localizable.Search.Scope.everywhere
        case .favorites: L10n.Localizable.Search.Scope.favorites
        case .watched: L10n.Localizable.Search.Scope.watched
        }
    }

    /// The field's prompt, which names where the search looks: the same words as the command
    /// bar's field, so the field that rises from the bar keeps them.
    var localizedPrompt: String {
        switch self {
        case .everywhere: L10n.Localizable.Shell.Search.prompt
        case .favorites: L10n.Localizable.Shell.Search.Prompt.favorites
        case .watched: L10n.Localizable.Shell.Search.Prompt.watched
        }
    }

    /// The scope's symbol in the scope menu, in SF Symbols 6.
    var systemImage: String {
        switch self {
        case .everywhere: "globe"
        case .favorites: "heart"
        case .watched: "eye"
        }
    }

    /// The filter set a search in this scope uses, which the Filters button opens: the
    /// search's own for Everywhere, Watched's for Watched. Favourites have none, as their list
    /// has none.
    var filterRange: FilterRange? {
        switch self {
        case .everywhere: .search
        case .watched: .watched
        case .favorites: nil
        }
    }
}
