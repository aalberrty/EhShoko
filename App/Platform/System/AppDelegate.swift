import Dependencies
import EhCore
import UIKit

/// Owns the interface orientation mask. Legacy behaviour: iPhone is portrait-only except in
/// the reader when landscape is enabled; iPad allows every orientation.
///
/// It is also where the system hands back the downloads of page translation models that
/// went on while the app was suspended or closed.
final class AppDelegate: NSObject, UIApplicationDelegate {
    private static var orientationMask: UIInterfaceOrientationMask =
        UIDevice.current.userInterfaceIdiom == .pad ? .all : [.portrait, .portraitUpsideDown]

    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        Self.orientationMask
    }

    /// The system woke the app, or started it in the background, because the transfers of a
    /// background session are done. The model store takes delivery and calls the handler.
    /// This is the only place the store is reached outside a screen, and it never runs at
    /// an ordinary launch.
    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        @Dependency(\.pageTranslationModelStore) var modelStore
        // The system suspends the app as soon as the session has delivered its events,
        // whenever the handler is called (iOS 18.2: half a second after this call).
        // Putting the files together, checking and compiling them takes longer, so the
        // app asks for that time itself.
        let time = BackgroundTime(named: "PageTranslationModels")
        modelStore.handleBackgroundSessionEvents(identifier: identifier) {
            completionHandler()
            time.end()
        }
    }

    static func setOrientationLock(_ lock: OrientationLock) {
        orientationMask = switch lock {
        case .portrait: [.portrait, .portraitUpsideDown]
        case .unlocked: .all
        }
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        for scene in scenes {
            for window in scene.windows {
                window.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
            }
            if lock == .portrait {
                scene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait))
            }
        }
    }
}

/// Time the app asks the system for while it is in the background: about half a minute.
/// It is given back when the work is done, or when the system says the time is up.
private final class BackgroundTime {
    private var identifier = UIBackgroundTaskIdentifier.invalid

    init(named name: String) {
        identifier = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
            self?.end()
        }
    }

    func end() {
        guard identifier != .invalid else { return }
        UIApplication.shared.endBackgroundTask(identifier)
        identifier = .invalid
    }
}
