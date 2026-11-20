import EhModels

/// What Ledger's Index, as the iPad's sidebar column, shows as chosen: the place at the
/// bottom of the stack, or Front Page, which the list column shows while no place is on the
/// path. The library itself is no row of the Index, so it chooses none.
public nonisolated enum LedgerIndexPlace: Hashable, Sendable {
    case list(GalleryListKind)
    /// A favourites folder, 0...9, or -1 for every folder.
    case folder(Int)

    /// The place `route`, the stack's first entry, stands for; `nil` for the library.
    public init?(base route: Route?) {
        switch route {
        case nil: self = .list(.frontpage)
        case .galleryList(.favorites): return nil
        case .galleryList(let kind): self = .list(kind)
        case .favoritesFolder(let route): self = .folder(route.folder)
        case .listSearch, .search, .typedSearch, .detail, .detailChild, .settings: self = .list(.frontpage)
        }
    }
}
