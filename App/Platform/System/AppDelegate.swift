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
        modelStore.handleBackgroundSessionEvents(identifier: identifier) { completionHandler() }
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
