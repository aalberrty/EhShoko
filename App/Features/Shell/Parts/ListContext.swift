import EhFeatures
import EhModels
import SwiftUI

/// Which list a `GalleryListScreen` shows, and how it sits in its screen
/// (`Design/designs/README.md` section 5.3). A list design must draw every one of these.
nonisolated struct ListContext: Hashable, Sendable {
    var kind: ListKind
    /// The screen's title, localized by the caller.
    var title: String
    /// Toplists only: what the period control offers, in order. The Top tab offers Popular
    /// first; the Toplists place offers the four periods.
    var rankedChoices: [RankedChoice]
    /// A first screen or the library passes a header and draws the screen's title itself: the
    /// list shows no large title of its own.
    var embedsInStart: Bool

    init(kind: ListKind, title: String, rankedChoices: [RankedChoice] = [], embedsInStart: Bool = false) {
        self.kind = kind
        self.title = title
        self.rankedChoices = rankedChoices
        self.embedsInStart = embedsInStart
    }
}

nonisolated enum ListKind: Hashable, Sendable {
    /// One place's list. `.favorites` is not a list: it is the library (`LibraryScreen`).
    case place(GalleryListKind)
    /// The site's search. `recordsHistory` is true for a search typed or picked on the search
    /// surface and false for one built from a tag, an uploader or a title.
    case search(keyword: String, recordsHistory: Bool)
    /// A search within Watched or the favourites, from the search surface's scopes.
    case scopedSearch(SearchScope, keyword: String)
    /// One favourites folder (0...9), or every folder (-1).
    case folder(Int)
}

/// One choice of a ranked list's period control.
nonisolated enum RankedChoice: Hashable, Sendable {
    case popular
    case period(ToplistsType)

    /// The four periods, as the site orders them.
    static let periods: [RankedChoice] = ToplistsType.allCases.map(RankedChoice.period)
    /// Popular, then the periods: the Top tab.
    static let popularAndPeriods: [RankedChoice] = [.popular] + periods
}

extension ListContext {
    /// The list of `place`, titled as the place is. `.favorites` has no list of its own.
    static func place(_ place: GalleryListKind, embedsInStart: Bool = false) -> ListContext {
        ListContext(
            kind: .place(place), title: place.title,
            rankedChoices: place == .toplists ? RankedChoice.periods : [],
            embedsInStart: embedsInStart
        )
    }

    /// The Top tab: Toplists with Popular as the first of its five choices.
    static let top = ListContext(
        kind: .place(.toplists), title: L10n.Localizable.Shell.Tab.top,
        rankedChoices: RankedChoice.popularAndPeriods
    )

    /// The account a signed-out list asks for, or `nil` for a list anyone can load.
    var signInKind: ListSignInKind? {
        switch kind {
        case .place(.watched), .scopedSearch(.watched, _): .watched
        case .folder, .scopedSearch(.favorites, _): .favorites
        default: nil
        }
    }

    /// The search scope a keyword typed on this list searches: its own list for Watched and
    /// the favourites, everywhere otherwise.
    var searchScope: SearchScope {
        switch kind {
        case .place(.watched), .scopedSearch(.watched, _): .watched
        case .folder, .scopedSearch(.favorites, _): .favorites
        default: .everywhere
        }
    }
}

/// Which signed-out state a list shows (the shared sign-in pieces name both).
nonisolated enum ListSignInKind: Hashable, Sendable {
    case watched
    case favorites
}

extension GalleryListKind {
    /// The place's name, as the tabs, the place menu and the list's title show it.
    var title: String {
        switch self {
        case .frontpage: L10n.Localizable.FrontpageView.Title.frontpage
        case .popular: L10n.Localizable.PopularView.Title.popular
        case .watched: L10n.Localizable.WatchedView.Title.watched
        case .toplists: L10n.Localizable.ToplistsView.Title.toplists
        case .history: L10n.Localizable.HistoryView.Title.history
        case .favorites: L10n.Localizable.Shell.Place.favorites
        }
    }

    /// The place's symbol (`wall.md` section 1), in SF Symbols 6.
    var systemImage: String {
        switch self {
        case .frontpage: "house"
        case .popular: "flame"
        case .watched: "eye"
        case .toplists: "crown"
        case .history: "clock"
        case .favorites: "heart"
        }
    }
}
