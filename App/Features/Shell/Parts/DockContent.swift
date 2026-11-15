// What a gallery page, and each of its child screens, declares as its bottom actions
// (`Design/designs/README.md` section 5.4, `spikes/S2.md` section 8). A part builds a
// `DockContent` value and hands it to the shell with `.dock(_:perform:)`; it never draws the
// dock. `ActionDock` (App/DesignSystem/Controls) draws it, under either bar.
//
// Everything here is a plain value, so the shell's dock entry stays `Equatable`: a change of
// content ("Read" becoming "Continue · page 1 of 48", Favourite filled) is a new value, and the
// closures that perform the actions travel separately, in the shell's reference box.

/// The bottom actions of one screen: up to three shapes, leading, centre and trailing, which
/// under the `command` bar are the bar's three shapes turned into these.
nonisolated struct DockContent: Equatable, Sendable {
    /// The round button at the leading edge: Favourite on every gallery design.
    var leading: DockItem?
    /// The tinted pill: Read, "Continue · page 23 of 48", "Read again"; "Write a comment" on
    /// Comments.
    var primary: DockItem
    /// What follows the pill: Comments (Shelf, Ledger), More (Wall).
    var trailing: DockTrailing?
    /// Whether the Favourite tip points at `leading` (`README.md` section 5.4). The gallery
    /// page sets it; a dock with only a pill has nothing to point at.
    var anchorsFavoriteTip: Bool

    init(leading: DockItem? = nil, primary: DockItem, trailing: DockTrailing? = nil, anchorsFavoriteTip: Bool = false) {
        self.leading = leading
        self.primary = primary
        self.trailing = trailing
        self.anchorsFavoriteTip = anchorsFavoriteTip
    }

    /// A dock with only the pill, such as Comments' "Write a comment".
    static func pill(_ item: DockItem) -> DockContent {
        DockContent(primary: item)
    }
}

/// One button of the dock: a round button (leading or trailing) or the pill.
nonisolated struct DockItem: Equatable, Sendable {
    /// The pill's text ("Continue", "Read"); a round button's VoiceOver label.
    var title: String
    /// The pill's second part, set lighter after the title ("page 23 of 48", "23 / 48").
    var detail: String?
    /// A round button's symbol; on the pill, an optional symbol before the title (Wall's ▶).
    var systemImage: String?
    /// What a tap does.
    var action: DockAction
    /// What a long press offers: Favourite's folder menu. `nil` for none.
    var menu: DockMenu?
    /// `false` greys the button out and ignores taps.
    var isEnabled: Bool
    /// Drawn at reduced emphasis but still tappable: an action that needs an account, whose
    /// tap asks the user to sign in.
    var isDimmed: Bool
    /// On the pill: the gallery whose reader it opens. The dock marks the pill as where that
    /// reader zooms out of (`readerSource(.dock(gid:))`); `nil` for a pill that opens no reader.
    var readerGalleryID: String?

    init(
        title: String, detail: String? = nil, systemImage: String? = nil, action: DockAction,
        menu: DockMenu? = nil, isEnabled: Bool = true, isDimmed: Bool = false, readerGalleryID: String? = nil
    ) {
        self.title = title
        self.detail = detail
        self.systemImage = systemImage
        self.action = action
        self.menu = menu
        self.isEnabled = isEnabled
        self.isDimmed = isDimmed
        self.readerGalleryID = readerGalleryID
    }
}

/// What follows the pill.
nonisolated enum DockTrailing: Equatable, Sendable {
    /// Round buttons, the last at the trailing edge: Comments; Rate and Comments on Ledger's
    /// regular width.
    case buttons([DockItem])
    /// A round button whose tap opens a menu: Wall's More.
    case menu(title: String, systemImage: String, menu: DockMenu)

    /// One round button.
    static func button(_ item: DockItem) -> DockTrailing {
        .buttons([item])
    }
}

/// A menu of the dock, in groups separated by dividers. Its entries are values; the menu's
/// views are built when it opens.
nonisolated struct DockMenu: Equatable, Sendable {
    var sections: [DockMenuSection]

    init(sections: [DockMenuSection]) {
        self.sections = sections
    }

    /// A menu of one group.
    init(_ entries: [DockMenuEntry]) {
        sections = [DockMenuSection(entries: entries)]
    }
}

nonisolated struct DockMenuSection: Equatable, Sendable {
    /// A heading over the group, or `nil`.
    var title: String?
    var entries: [DockMenuEntry]

    init(title: String? = nil, entries: [DockMenuEntry]) {
        self.title = title
        self.entries = entries
    }
}

nonisolated struct DockMenuEntry: Equatable, Sendable, Identifiable {
    var title: String
    var systemImage: String?
    var action: DockAction
    /// Shown with a checkmark: the folder a favourite is in.
    var isSelected: Bool
    var isEnabled: Bool
    /// Drawn in red: Remove from favourites.
    var isDestructive: Bool

    var id: DockAction { action }

    init(
        title: String, systemImage: String? = nil, action: DockAction,
        isSelected: Bool = false, isEnabled: Bool = true, isDestructive: Bool = false
    ) {
        self.title = title
        self.systemImage = systemImage
        self.action = action
        self.isSelected = isSelected
        self.isEnabled = isEnabled
        self.isDestructive = isDestructive
    }
}

/// What a dock button or menu entry asks the gallery page to do. The page performs it; the dock
/// only reports which one was chosen.
nonisolated enum DockAction: Hashable, Sendable {
    /// A one-tap Favourite: into the folder used last.
    case favorite
    /// A folder chosen in the folder menu (0...9).
    case favoriteIn(folder: Int)
    case unfavorite
    /// Read, Continue or Read again: the pill says which.
    case read
    case comments
    case writeComment
    case rate
    case archive
    case torrents
    case galleryInfos
    case similarGalleries
    case share
    /// An action only one design offers, named by that design.
    case other(String)
}
