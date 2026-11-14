import EhModels
import Observation

/// App-level navigation state (`Design/designs/README.md` section 6): the selected tab and one
/// stack per tab for the `tabs` bar, the place for the `command` bar (which uses the `home`
/// stack alone), the Settings sheet, the gallery sheet for links from outside the app, and
/// what is presented over everything (the reader from Continue, the greeting, the offer).
@Observable
public final class AppRouter {
    public private(set) var selectedTab: AppTab = .home

    public let home = StackRouter()
    public let watched = StackRouter()
    public let top = StackRouter()
    public let library = StackRouter()
    public let search = StackRouter()

    /// The stack of the Settings sheet.
    public let settings = StackRouter()
    public private(set) var isSettingsPresented = false

    /// A gallery opened from a deep link, a clipboard link or the share extension.
    /// It is shown as a sheet with its own stack (`presented`) on top of the tabs.
    public private(set) var presentedGallery: Gallery?
    public let presented = StackRouter()

    /// The daily "New Dawn" greeting to announce, shown as a sheet over everything else.
    /// Any feature that receives a greeting worth showing sets it; the shell presents it.
    public var presentedGreeting: Greeting?

    /// A reader opened from Continue, presented by the shell.
    public var reading: ReadingRequest?

    /// The offer after install is due. The shell presents it only when `showsOffer` allows.
    public var offer = false

    /// How many times each tab was re-selected while already showing its root screen.
    /// Tab roots observe their counter and reload when it changes.
    public private(set) var rootReselections: [AppTab: Int] = [:]

    /// The place of the `home` stack's root: `.start`, or under Wall's first screen, whose root
    /// is itself a list, the list the place menu chose. It is the command bar's place when
    /// the `home` stack does not say otherwise (see `place`).
    public private(set) var rootPlace: Place = .start

    public init() {}

    // MARK: Tabs

    public func stack(for tab: AppTab) -> StackRouter {
        switch tab {
        case .home: home
        case .watched: watched
        case .top: top
        case .library: library
        case .search: search
        }
    }

    /// The selected tab's stack; under `command`, always `home`.
    public var selectedStack: StackRouter { stack(for: selectedTab) }

    /// Selects a tab. Selecting the current tab pops its stack to the root, or, when it is
    /// already at the root, bumps its reselection counter so the root screen can reload.
    public func select(_ tab: AppTab) {
        guard tab == selectedTab else {
            selectedTab = tab
            return
        }
        let stack = stack(for: tab)
        if stack.isAtRoot {
            rootReselections[tab, default: 0] += 1
        } else {
            stack.popToRoot()
        }
    }

    public func rootReselectionCount(for tab: AppTab) -> Int {
        rootReselections[tab, default: 0]
    }

    // MARK: Places

    /// The place the command bar shows: the list at the bottom of the `home` stack when one
    /// was pushed there (by the place menu, or by a row of Ledger's Index), else the root's.
    /// Going back to Home or the Index so gives `.start` without anyone setting it.
    public var place: Place {
        home.path.first.flatMap(Place.init(baseRoute:)) ?? rootPlace
    }

    /// Moves the command bar to `place`, as the first screen `start` wants it
    /// (`Design/designs/README.md` section 5.1). Wall's root is the place itself and is
    /// replaced in place; Shelf and Ledger keep their root and show the list over it.
    public func go(to place: Place, start: DesignStyle) {
        home.closeSidePane()
        switch start {
        case .wall:
            rootPlace = place == .list(.frontpage) ? .start : place
            home.popToRoot()
        case .shelf, .ledger:
            rootPlace = .start
            switch place {
            case .start: home.popToRoot()
            case .list(let kind): home.path = [.galleryList(kind)]
            }
        }
    }

    /// After the bar or the first screen changed: every stack at its root with its side pane
    /// closed, Home selected, the first screen as the place. The sheets stay up.
    public func resetNavigation() {
        for tab in AppTab.allCases {
            let stack = stack(for: tab)
            stack.popToRoot()
            stack.closeSidePane()
        }
        selectedTab = .home
        rootPlace = .start
    }

    // MARK: Settings

    /// The Settings sheet's path; `nil` when the sheet is closed.
    public var settingsPath: [Route]? { isSettingsPresented ? settings.path : nil }

    /// Opens the Settings sheet showing `path` (empty: the Settings page itself).
    public func presentSettings(_ path: [Route] = []) {
        settings.path = path
        isSettingsPresented = true
    }

    /// Closes the Settings sheet. Its path is replaced the next time it opens.
    public func dismissSettings() {
        isSettingsPresented = false
    }

    // MARK: The offer

    /// The offer's queue rule: it waits until the app is unlocked and neither the greeting nor
    /// the gallery sheet is showing.
    public func showsOffer(isUnlocked: Bool) -> Bool {
        offer && isUnlocked && presentedGreeting == nil && presentedGallery == nil
    }

    // MARK: Gallery sheet

    /// Presents `gallery` in the gallery sheet. `target` is what the link pointed at inside the
    /// gallery; the detail screen takes it once with `takePresentedGalleryTarget(for:)`.
    public func present(_ gallery: Gallery, target: GalleryLinkTarget? = nil) {
        presented.popToRoot()
        presentedGalleryTarget = target
        presentedGallery = gallery
    }

    public func dismissPresentedGallery() {
        presentedGallery = nil
        presentedGalleryTarget = nil
        presented.popToRoot()
    }

    /// What the link that opened the presented gallery pointed at, if anything.
    ///
    /// Not observed: the sheet takes it while building its root screen, and taking it must not
    /// invalidate the view being built.
    @ObservationIgnored public private(set) var presentedGalleryTarget: GalleryLinkTarget?

    /// Returns the presented gallery's link target and forgets it, so it is honoured once.
    /// `nil` when `gid` is not the presented gallery or there is no target.
    public func takePresentedGalleryTarget(for gid: String) -> GalleryLinkTarget? {
        guard presentedGallery?.gid == gid, let target = presentedGalleryTarget else { return nil }
        presentedGalleryTarget = nil
        return target
    }
}

/// The part of a gallery a link points at, beyond the gallery itself.
nonisolated public enum GalleryLinkTarget: Hashable, Sendable {
    /// An image page (`/s/<key>/<gid>-<page>`): open the reader at this 1-based page. The page
    /// is already stored as the gallery's reading progress when the gallery is presented.
    case page(Int)
    /// A comment anchor (`/g/<gid>/<token>/#c<id>`): open the comments scrolled to this comment.
    case comment(String)
}

private extension Place {
    /// The place a route at the bottom of the `home` stack stands for, if it is one.
    nonisolated init?(baseRoute: Route) {
        switch baseRoute {
        case .galleryList(let kind): self = .list(kind)
        case .favoritesFolder: self = .list(.favorites)
        case .listSearch, .search, .typedSearch, .detail, .detailChild, .settings: return nil
        }
    }
}
