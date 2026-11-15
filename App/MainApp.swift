import Dependencies
import EhCore
import SwiftUI

@main
struct MainApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        PerformanceSignposts.appStarted()
        // Both run before anything reads a dependency or loads an image; neither touches disk.
        // The image cache, whose creation does, gets its limits in the launch sequence.
        ImageDownloaderConfiguration.configure()
        prepareDependencies {
            $0.domainFronting = .appWide
            #if DEBUG || HARNESS
            // The part harness, launched as the whole app, runs on a database and a client
            // of its own.
            if HarnessRequest.atLaunch == .part {
                PartHarnessDependencies.install(in: &$0)
            }
            #endif
        }
    }

    var body: some Scene {
        WindowGroup {
            HarnessGate { AppShellView() }
        }
    }
}
