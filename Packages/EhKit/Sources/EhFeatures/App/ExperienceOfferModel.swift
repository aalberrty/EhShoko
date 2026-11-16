import Dependencies
import EhCore
import EhModels
import Observation

/// The offer after install: a sheet, shown once per install, that plays the three presets and
/// offers three ways out (`Design/designs/settings.md`, "The offer after install").
///
/// - **When.** `AppModel` asks after each activation's follow-ups, so behind the app lock and
///   after the greeting has been fetched. The offer is queued when `experienceOfferShown` is
///   false, the launch is ready, the app is unlocked and no link from outside is open or
///   being opened. The router then presents it once nothing else is presented
///   (`AppRouter.showsOffer`), so it also waits for the greeting to be dismissed.
/// - **Links first.** A link's gallery that arrives while the offer is queued or up takes its
///   place; the offer waits for the next activation.
/// - **Once.** The flag is set when the sheet appears, so it is never shown twice.
/// - **Three ways out.** "Use …" applies the selected preset at once and closes; "Set up step
///   by step" closes and then opens Settings at the wizard with that preset as its start;
///   "Not now", or a swipe, closes and changes nothing.
@Observable
public final class ExperienceOfferModel {
    /// The preset the tiles select and "Use …" applies. Shelf at first, as it is the default.
    public var selection: DesignStyle = .shelf

    private let router: AppRouter
    private let lock: AppLockModel

    /// The wizard's starting preset, once "Set up step by step" was chosen: Settings opens
    /// when the offer has gone (`didDismiss()`), as two sheets cannot be shown from one place
    /// at once.
    @ObservationIgnored private var pendingSetup: DesignStyle?

    @ObservationIgnored @Dependency(\.settings) private var settings

    /// Cheap: reads no setting and starts nothing.
    init(router: AppRouter, lock: AppLockModel) {
        self.router = router
        self.lock = lock
    }

    // MARK: When

    /// Whether the sheet is up: queued, and nothing else presented (the router's rule).
    public var isPresented: Bool {
        router.showsOffer(isUnlocked: !lock.isLocked)
    }

    /// Whether the offer should be queued now: never shown, the launch ready, the app
    /// unlocked, and no link from outside open or being opened. The greeting is not part of
    /// this: the queued offer waits for it to be dismissed.
    func isDue(isReady: Bool, isUnlocked: Bool, isOpeningLink: Bool) -> Bool {
        !settings.experienceOfferShown && isReady && isUnlocked
            && !isOpeningLink && router.presentedGallery == nil
    }

    /// Queues the offer when it is due. Called after an activation's follow-ups.
    func offerIfDue(isReady: Bool, isUnlocked: Bool, isOpeningLink: Bool) {
        guard !router.offer, isDue(isReady: isReady, isUnlocked: isUnlocked, isOpeningLink: isOpeningLink) else {
            return
        }
        router.offer = true
    }

    /// The sheet appeared: it is never offered again.
    public func appeared() {
        settings.experienceOfferShown = true
    }

    /// A link's gallery was presented. It takes precedence: a queued or showing offer is
    /// withdrawn and waits for the next activation (once it has appeared, it does not come
    /// back), and a wizard asked for while the offer was closing is not opened.
    public func linkPresented() {
        pendingSetup = nil
        if router.offer {
            router.offer = false
        }
    }

    // MARK: Ways out

    /// "Use …": applies the selected preset at once and closes.
    public func use() {
        settings.applyDesignPreset(selection)
        router.offer = false
    }

    /// "Set up step by step": closes; Settings opens at the wizard, starting from the selected
    /// preset, once the sheet has gone.
    public func setUp() {
        pendingSetup = selection
        router.offer = false
    }

    /// "Not now", or the sheet swiped away: closes and changes nothing.
    public func notNow() {
        router.offer = false
    }

    /// The sheet has gone, by whatever means. Opens the wizard if "Set up step by step" asked
    /// for it.
    public func didDismiss() {
        guard let start = pendingSetup else { return }
        pendingSetup = nil
        router.presentSettings([.settings(.designSetup(start: start))])
    }
}
