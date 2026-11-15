import EhCore
import EhFeatures
import SwiftUI
import TipKit
import UIKit

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
        if await isSettled() { return }
        await quickFavorite.donate()
    }

    /// Whether the tip can never show again: read off the main actor, from TipKit's store.
    @concurrent
    static func isSettled() async -> Bool {
        if case .invalidated = FavoriteTip().status { true } else { false }
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
            content.modifier(FavoriteTipSource())
        } else {
            content
        }
    }
}

private struct FavoriteTipSource: ViewModifier {
    @Environment(SettingsStore.self) private var settings
    @Environment(UserStore.self) private var userStore

    func body(content: Content) -> some View {
        content.background {
            FavoriteTipPresenter(tip: FavoriteTip(folderName: userStore.favoriteFolderName(settings.lastFavoriteFolder)))
        }
    }
}

// MARK: The popover

/// TipKit's popover, presented from UIKit (`TipUIPopoverViewController`) rather than with
/// `popoverTip`. SwiftUI's `popoverTip` is modal: while it showed, a tap on the Favourite
/// button only closed the tip, and the button did nothing. Here the button's frame is the
/// popover's passthrough view: a tap or a long press on it reaches the button, as without
/// the tip, and closes the tip; a tap anywhere else closes it as it closes any popover.
/// Everything else is TipKit's: the look, the close button, the counting of its one showing.
private struct FavoriteTipPresenter: UIViewRepresentable {
    let tip: FavoriteTip

    func makeUIView(context: Context) -> FavoriteTipSourceView {
        FavoriteTipSourceView(tip: tip)
    }

    func updateUIView(_ view: FavoriteTipSourceView, context: Context) {
        view.tip = tip
    }

    static func dismantleUIView(_ view: FavoriteTipSourceView, coordinator: ()) {
        view.stop()
    }
}

/// A clear view behind the Favourite button, the popover's source and passthrough view.
///
/// While it is in a window it follows TipKit's verdict on the tip until the tip is settled,
/// which after its one showing it always is: then it waits for nothing at all.
private final class FavoriteTipSourceView: UIView {
    var tip: FavoriteTip
    private var observation: Task<Void, Never>?
    private weak var popover: TipUIPopoverViewController?
    private var isForwardingTouch = false

    init(tip: FavoriteTip) {
        self.tip = tip
        super.init(frame: .zero)
        backgroundColor = .clear
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            stop()
        } else if observation == nil {
            observation = Task { [weak self] in await self?.follow() }
        }
    }

    /// Asked by the popover's dimming view for a touch while the tip shows. UIKit gives the
    /// touch to whatever this returns, so a touch on the button gets the view the screen
    /// itself would have given it (the button, as without the tip) and closes the tip.
    /// Otherwise this view takes no touch.
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard !isForwardingTouch, isShowingPopover, self.point(inside: point, with: event),
              let screen = nearestViewController?.view else { return nil }
        // The screen's own hit test may come back here; it must not find this view then.
        isForwardingTouch = true
        defer { isForwardingTouch = false }
        // After this touch has been delivered, not while UIKit is still looking for its view.
        Task { [weak self] in self?.closePopover(animated: true) }
        return screen.hitTest(convert(point, to: screen), with: event)
    }

    func stop() {
        observation?.cancel()
        observation = nil
        closePopover(animated: false)
    }

    private func follow() async {
        if await FavoriteTip.isSettled() { return }
        for await status in tip.statusUpdates {
            if Task.isCancelled { return }
            switch status {
            case .available:
                present()
            case .invalidated:
                // Settled for good, perhaps only now that TipKit has read its store: nothing
                // more to wait for on this screen.
                closePopover(animated: true)
                return
            default:
                closePopover(animated: true)
            }
        }
    }

    private var isShowingPopover: Bool {
        popover?.presentingViewController != nil
    }

    private func present() {
        // Not over another presentation: the dock is not what the user is looking at then.
        guard !isShowingPopover, let presenter = nearestViewController, presenter.presentedViewController == nil else {
            return
        }
        let popover = TipUIPopoverViewController(tip, sourceItem: self)
        popover.popoverPresentationController?.permittedArrowDirections = .down
        popover.popoverPresentationController?.passthroughViews = [self]
        presenter.present(popover, animated: true)
        self.popover = popover
    }

    private func closePopover(animated: Bool) {
        guard let popover, isShowingPopover, !popover.isBeingDismissed else { return }
        popover.dismiss(animated: animated)
    }

    private var nearestViewController: UIViewController? {
        var responder: UIResponder? = next
        while let current = responder {
            if let controller = current as? UIViewController { return controller }
            responder = current.next
        }
        return nil
    }
}
