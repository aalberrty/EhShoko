import EhCore
import EhFeatures
import EhModels
import SwiftUI

/// Where the Index's rows lead. One value for the phone page and the iPad column: the path
/// is the same in both (`spikes/F7.md` section 2.2), so nothing here asks which one it is.
struct LedgerIndexNavigation {
    let appRouter: AppRouter
    /// The `home` stack: under `command` the only one, under `tabs` the Home tab's.
    let stack: StackRouter

    /// A list: pushed over the Index on a phone, the list column's root beside it.
    func open(_ kind: GalleryListKind) {
        appRouter.go(to: .list(kind), start: .ledger)
    }

    /// A favourites folder's list; `-1` is every folder. Like a list it becomes the place,
    /// so on iPad it is chosen in the column as the lists are.
    func openFolder(_ index: Int) {
        stack.closeSidePane()
        stack.path = [.favoritesFolder(index)]
    }

    /// A saved search runs everywhere, over whatever is showing.
    func run(_ keyword: String) {
        stack.push(SearchSurfaceModel.route(for: keyword, in: .everywhere))
    }

    func continueReading(_ item: ContinueItem) {
        appRouter.reading = ReadingRequest(gallery: item.gallery, page: item.page)
    }

    func signIn() {
        appRouter.presentSettings([.settings(.account), .settings(.login)])
    }
}

/// What the iPad column shows as chosen: the place at the bottom of the stack, or Front
/// Page, which the list column shows while no place is on the path.
nonisolated enum LedgerIndexPlace: Hashable, Sendable {
    case list(GalleryListKind)
    case folder(Int)

    init?(base route: Route?) {
        switch route {
        case nil: self = .list(.frontpage)
        case .galleryList(.favorites): return nil
        case .galleryList(let kind): self = .list(kind)
        case .favoritesFolder(let index): self = .folder(index)
        case .listSearch, .search, .typedSearch, .detail, .detailChild, .settings: self = .list(.frontpage)
        }
    }
}

extension LedgerIndexNavigation {
    func choose(_ place: LedgerIndexPlace) {
        switch place {
        case .list(let kind): open(kind)
        case .folder(let index): openFolder(index)
        }
    }
}

// MARK: The rows' values

/// One row of LISTS: the place and what its row says about it.
struct LedgerIndexListItem: Identifiable, Equatable {
    let kind: GalleryListKind
    /// The filter in short form, History's size, or "Sign in"; `nil` for none.
    let value: String?

    var id: GalleryListKind { kind }

    /// Front Page and Watched show their filter when it narrows anything and `showsFilters`;
    /// Watched asks to sign in when signed out; History shows its size once it is known;
    /// Popular and Toplists show nothing (v3 does not keep Toplists' period).
    static func items(
        frontPage: FilterSummary, watched: FilterSummary, isSignedIn: Bool, historyCount: Int?,
        showsFilters: Bool
    ) -> [Self] {
        func summary(_ filter: FilterSummary) -> String? {
            showsFilters && !filter.isDefault ? filter.shortText : nil
        }
        return [
            Self(kind: .frontpage, value: summary(frontPage)),
            Self(kind: .popular, value: nil),
            Self(kind: .watched, value: isSignedIn ? summary(watched) : L10n.Localizable.Start.Ledger.signIn),
            Self(kind: .toplists, value: nil),
            Self(kind: .history, value: historyCount.map { $0.formatted() }),
        ]
    }
}
