import EhFeatures
import EhModels

/// The places the command bar moves between, for one first screen: what the menu lists, in
/// which order, and what follows what when the bar is swiped.
///
/// A value of the two things the answer depends on, so the bar's views can compare it.
nonisolated struct CommandBarPlaces: Equatable, Sendable {
    /// The first screen's design.
    let start: DesignStyle
    /// Ledger's Index stands beside the list as a column (regular width). The Index is then
    /// always on screen and is not a place of the bar's, and the stack's root is Front Page.
    let hasLeadingColumn: Bool

    /// The menu's entries, in order. Wall's root is itself a list, so its first entry, Front
    /// Page, is `.start`; Shelf's and Ledger's is their first screen.
    var entries: [Place] {
        let lists: [Place] = [.list(.popular), .list(.watched), .list(.toplists), .list(.history), .list(.favorites)]
        switch start {
        case .wall, .shelf: return [.start] + lists
        case .ledger: return (hasLeadingColumn ? [] : [.start]) + [.list(.frontpage)] + lists
        }
    }

    /// The place the bar names while the router is on `place`: beside the Index column the
    /// root shows Front Page, so that is what an empty stack is called.
    func shown(_ place: Place) -> Place {
        hasLeadingColumn && place == .start ? .list(.frontpage) : place
    }

    /// On Ledger's Index itself the menu is not shown: the Index is the menu. It is shown on
    /// every screen over it, and always beside the Index column.
    func showsMenu(isAtRoot: Bool) -> Bool {
        !(start == .ledger && !hasLeadingColumn && isAtRoot)
    }

    /// The position of `place` among the entries. A plain Front Page list under a first
    /// screen that holds Front Page itself (Shelf's Home) counts as that first screen.
    func index(of place: Place) -> Int? {
        if let index = entries.firstIndex(of: place) { return index }
        return place == .list(.frontpage) ? entries.firstIndex(of: .start) : nil
    }

    func isCurrent(_ entry: Place, at place: Place) -> Bool {
        index(of: place) == entries.firstIndex(of: entry)
    }

    /// The place `offset` entries after `place` (before it, when negative); `nil` past
    /// either end: the swipe does not wrap around.
    func neighbour(of place: Place, by offset: Int) -> Place? {
        guard let index = index(of: place), entries.indices.contains(index + offset) else { return nil }
        return entries[index + offset]
    }

    /// Which way the label moves from `old` to `new`: 1 towards later entries, -1 towards
    /// earlier ones, 0 when the order does not say.
    func direction(from old: Place, to new: Place) -> Int {
        guard let from = index(of: old), let to = index(of: new) else { return 0 }
        return (to - from).signum()
    }

    /// What to hand the router for the entry `entry` while it is on `place`. Beside the
    /// Index column the empty stack already shows Front Page: choosing Front Page there
    /// returns to that root instead of putting the same list over it.
    func destination(for entry: Place, from place: Place) -> Place {
        hasLeadingColumn && entry == .list(.frontpage) && place == .start ? .start : entry
    }

    /// What the field opens and says for the top screen `top` of the stack on `place`: the
    /// keyword on a list of results, else the prompt for the scope of where the user is.
    func field(top: Route?, place: Place) -> CommandBarField {
        switch top {
        case .typedSearch(let keyword), .search(let keyword):
            return CommandBarField(scope: .everywhere, prompt: .everywhere, keyword: keyword)
        case .listSearch(let scope, let keyword):
            return CommandBarField(scope: scope, prompt: CommandBarPrompt(scope), keyword: keyword)
        case .galleryList(.watched):
            return CommandBarField(scope: .watched, prompt: .watched)
        case .galleryList(.favorites), .favoritesFolder:
            return CommandBarField(scope: .favorites, prompt: .favorites)
        case .galleryList, .detail, .detailChild, .settings:
            return CommandBarField(scope: .everywhere, prompt: .everywhere)
        case nil:
            switch place {
            case .list(.watched): return CommandBarField(scope: .watched, prompt: .watched)
            case .list(.favorites): return CommandBarField(scope: .favorites, prompt: .favorites)
            // Ledger's Index, as drawn: its field also takes a pasted link.
            case .start where start == .ledger && !hasLeadingColumn:
                return CommandBarField(scope: .everywhere, prompt: .link)
            case .start, .list: return CommandBarField(scope: .everywhere, prompt: .everywhere)
            }
        }
    }
}

/// What the bar's field stands for.
nonisolated struct CommandBarField: Equatable, Sendable {
    /// The scope the search surface opens on.
    var scope: SearchScope
    var prompt: CommandBarPrompt
    /// The keyword of the results on screen, which the field shows in the prompt's place.
    var keyword: String?
}

nonisolated enum CommandBarPrompt: Equatable, Sendable {
    case everywhere, favorites, watched, link

    init(_ scope: SearchScope) {
        switch scope {
        case .everywhere: self = .everywhere
        case .favorites: self = .favorites
        case .watched: self = .watched
        }
    }
}

// MARK: Names and symbols

extension CommandBarPlaces {
    /// The place's name under this first screen, which has a name of its own.
    func title(of place: Place) -> String {
        switch place {
        case .list(let kind): kind.title
        case .start:
            switch start {
            case .shelf: L10n.Localizable.Shell.Place.home
            case .wall: GalleryListKind.frontpage.title
            case .ledger: L10n.Localizable.Shell.Place.index
            }
        }
    }

    func systemImage(of place: Place) -> String {
        switch place {
        case .list(let kind): kind.systemImage
        case .start: start == .ledger ? "list.bullet" : "house"
        }
    }
}

extension CommandBarPrompt {
    var text: String {
        switch self {
        case .everywhere: L10n.Localizable.Shell.Search.prompt
        case .favorites: L10n.Localizable.Shell.Search.Prompt.favorites
        case .watched: L10n.Localizable.Shell.Search.Prompt.watched
        case .link: L10n.Localizable.Shell.Search.Prompt.link
        }
    }

    /// The plain prompt, for a field too narrow for the one that names its scope: the place
    /// capsule beside it already says where the search looks.
    var shortText: String? {
        self == .everywhere ? nil : L10n.Localizable.Shell.Search.prompt
    }
}
