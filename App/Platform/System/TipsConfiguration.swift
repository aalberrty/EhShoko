import Dependencies
import EhCore
import Foundation
import Synchronization
import TipKit

/// TipKit, which keeps the Favourite tip's state in a small store of its own
/// (`Design/designs/README.md` section 5.4). There is no setting for the tip: whether it was
/// earned, shown or settled lives in that store alone.
///
/// `Tips.configure` opens the store, which is file I/O, so it runs once, off the main actor,
/// after the first screen is up: never on the launch path. Until it has run TipKit shows no
/// tip, and the tip's anchor costs nothing more than an unconfigured `popoverTip`.
nonisolated enum TipsConfiguration {
    private static let isConfigured = Mutex(false)

    /// Opens TipKit's store. Any later call does nothing, so the launch sequence may call it
    /// without knowing whether something else (a harness) already has.
    @concurrent
    static func configure() async {
        let isFirstCall = isConfigured.withLock { isConfigured in
            defer { isConfigured = true }
            return !isConfigured
        }
        guard isFirstCall else { return }
        do {
            #if DEBUG
            try DebugRequest.atLaunch?.applyBeforeConfiguring()
            #endif
            // One tip in the app, so no pacing between tips: it shows as soon as it is earned.
            try Tips.configure([.displayFrequency(.immediate), .datastoreLocation(.applicationDefault)])
        } catch {
            @Dependency(\.appLogger) var logger
            logger.warning("TipKit could not be configured: \(error)", category: "Tips")
        }
    }
}

#if DEBUG
extension TipsConfiguration {
    /// `-Tips reset|show|hide` at launch, for UI tests and screenshots.
    ///
    /// - `reset` empties TipKit's store, so the tip is earned again by the next one-tap
    ///   Favourite, as on a fresh install.
    /// - `show` shows the tip whenever its anchor is on screen, whatever its rules say.
    /// - `hide` shows no tip at all, for runs that must not be interrupted by one.
    nonisolated enum DebugRequest: String {
        case reset, show, hide

        static var atLaunch: DebugRequest? {
            UserDefaults.standard.string(forKey: "Tips").flatMap(DebugRequest.init(rawValue:))
        }

        /// TipKit takes all three before `Tips.configure`; a reset after it throws.
        func applyBeforeConfiguring() throws {
            switch self {
            case .reset: try Tips.resetDatastore()
            case .show: Tips.showTipsForTesting([FavoriteTip.self])
            case .hide: Tips.hideAllTipsForTesting()
            }
        }
    }
}
#endif
