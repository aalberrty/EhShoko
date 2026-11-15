import EhCore
import EhFeatures
import SwiftUI
import TipKit

/// The tip that teaches Favourite's folder menu (`Design/designs/README.md` section 5.4):
/// "Touch and hold to choose a folder", pointing at the dock's Favourite button.
///
/// It is earned by the first one-tap Favourite the site accepts, anywhere (a list's menu or
/// swipe, a gallery page's dock), and shows once, the next time the Favourite button is on
/// screen (at once if the tap was there). It is settled for good when it has been shown, when
/// it is closed, or when a folder is chosen from a menu, which means the menu has been found.
/// TipKit keeps all of that in its own store (`TipsConfiguration`).
nonisolated struct FavoriteTip: Tip {
    /// A one-tap Favourite that the site accepted.
    static let quickFavorite = Tips.Event(id: "favorite.quick")

    // Localized by the anchor, on the main actor, where `L10n` lives.
    private let titleText: String
    private let messageText: String

    /// The tip as TipKit settles it; its texts are not needed for that.
    init() {
        titleText = ""
        messageText = ""
    }

    @MainActor
    init(folderName: String) {
        titleText = L10n.Localizable.Tip.Favorite.title
        messageText = L10n.Localizable.Tip.Favorite.message(folderName)
    }

    /// Fixed, so the state TipKit stored survives a rename of the type.
    var id: String { "favorite.folder-menu" }
    var title: Text { Text(titleText) }
    var message: Text? { Text(messageText) }

    var rules: [Rule] {
        #Rule(Self.quickFavorite) { $0.donations.count > 0 }
    }

    var options: [any TipOption] {
        MaxDisplayCount(1)
    }
}

// MARK: Events

extension FavoriteTip {
    /// Tells the tip about a favourite that a model reported (`favoriteReport` of the list's
    /// actions model and of the gallery page's model): a one-tap Favourite earns it, a folder
    /// chosen from a menu settles it. Call it where the report is observed, beside the HUD;
    /// it is one call per favourite, and TipKit's store is written off the main actor.
    @MainActor
    static func record(_ report: FavoriteReport) {
        switch report.kind {
        case .quick:
            Task { await donateQuickFavorite() }
        case .chosen:
            Task { await settle() }
        case .moved:
            break
        }
    }

    @concurrent
    private static func donateQuickFavorite() async {
        // Once the tip is settled the event can change nothing: stop writing it to the store.
        if case .invalidated = FavoriteTip().status { return }
        await quickFavorite.donate()
    }

    @concurrent
    private static func settle() async {
        FavoriteTip().invalidate(reason: .actionPerformed)
    }
}

// MARK: The anchor

extension View {
    /// Points the Favourite tip at this view when `isAnchor`: the dock's Favourite button on a
    /// gallery page (`DockContent.anchorsFavoriteTip`). The tip is TipKit's popover, above
    /// the button with its arrow pointing down at it, in the system's look (glass on iOS 26).
    ///
    /// Not an anchor, it adds nothing. An anchor reads the folder a tap saves to, for the
    /// tip's text; that changes only when a folder is chosen or renamed.
    func favoriteTip(isAnchor: Bool) -> some View {
        modifier(FavoriteTipAnchor(isAnchor: isAnchor))
    }
}

private struct FavoriteTipAnchor: ViewModifier {
    let isAnchor: Bool

    func body(content: Content) -> some View {
        if isAnchor {
            content.modifier(FavoriteTipPopover())
        } else {
            content
        }
    }
}

private struct FavoriteTipPopover: ViewModifier {
    @Environment(SettingsStore.self) private var settings
    @Environment(UserStore.self) private var userStore

    func body(content: Content) -> some View {
        content.popoverTip(
            FavoriteTip(folderName: userStore.favoriteFolderName(settings.lastFavoriteFolder)),
            arrowEdge: .bottom
        )
    }
}
