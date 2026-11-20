import Dependencies
import EhCore
import EhFeatures
import EhModels
import SwiftUI

/// The root of the app: the launch screens until the database is ready, then `ShellRoot`.
///
/// It also owns everything around the features: the look, the tint and the colour scheme,
/// links opened from outside, the scene lifecycle and the privacy blur and lock, which live
/// in a window above this one (see `SceneWindowBridge`).
struct AppShellView: View {
    @State private var model: AppModel = {
        let model = AppModel()
        model.lock.localizedReason = L10n.Localizable.LocalAuthorization.reason
        // Before anything is shown, so the first frame is already on the remembered place.
        ShellLaunch.restorePlace(in: model.router)
        return model
    }()

    @Environment(\.scenePhase) private var scenePhase

    // The settings decide the first frame's colours. The other shared services are injected
    // by `ShellRoot`: the launch creates them off the main actor before the shell appears.
    @Dependency(\.settings) private var settings

    var body: some View {
        ZStack {
            if model.launchState == .ready {
                ShellRoot(model: model)
                    .transition(.opacity)
            } else {
                LaunchStatusView(model: model)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.25), value: model.launchState == .ready)
        // The one place the look is set: every screen, sheet and cover below inherits it.
        .lookEnvironment(Look(settings.look), accent: settings.accentColor)
        // And for the colours UIKit resolves itself: a list's separators (`LookTrait`).
        .windowLook(Look(settings.look))
        .environment(model.router)
        .environment(settings)
        .background {
            SceneWindowBridge(
                colorScheme: settings.preferredColorScheme,
                look: Look(settings.look),
                accentColor: settings.accentColor,
                lock: model.lock,
                isPrivacyOverlayVisible: model.lock.blurRadius > 0 || model.lock.isLocked,
                unlock: model.unlock
            )
        }
        .onAppear { PerformanceSignposts.rootAppeared() }
        .onOpenURL { model.links.open($0) }
        .harnessLaunchActions { model.links.open($0) }
        .onChange(of: scenePhase, initial: true) { _, phase in
            model.scenePhaseChanged(to: AppModel.ScenePhase(phase))
        }
        .task(id: model.launchAttempt) {
            await model.launch()
        }
        .task { await model.followDomainFrontingSetting() }
    }
}

private extension AppModel.ScenePhase {
    init(_ phase: SwiftUI.ScenePhase) {
        switch phase {
        case .active: self = .active
        case .background: self = .background
        default: self = .inactive
        }
    }
}

#Preview {
    AppShellView()
}
