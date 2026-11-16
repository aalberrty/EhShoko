import EhFeatures
import EhModels
import SwiftUI

/// The privacy blur over the whole app and, when the auto-lock expired, the lock control
/// (legacy: the blurred tab view with an 80 pt `lock.fill` button).
///
/// Not glass (`Design/designs/README.md` section 13: a cover, not a control): the existing blur
/// over the look's ground, and the lock on the look's fill. The look changes only colours: the
/// blur, its radius and the material that hide the app are the same in every look.
struct PrivacyOverlayView: View {
    let lock: AppLockModel
    let snapshot: PrivacySnapshot
    let unlock: () -> Void
    // Hosted in its own window above the app (`SceneWindowBridge`), outside the root that puts
    // the look into the environment, so the bridge hands it the root's look and accent.
    let look: Look
    let accentColor: RGBColor

    var body: some View {
        ZStack {
            if let view = snapshot.view {
                // The ground shows at the blurred edges instead of the sharp window below.
                look.background
                SnapshotView(view: view)
                    .autoBlur(radius: lock.blurRadius)
            } else {
                Rectangle()
                    .fill(.ultraThickMaterial)
                    .opacity(lock.blurRadius > 0 || lock.isLocked ? 1 : 0)
                    .animation(.linear(duration: 0.1), value: lock.blurRadius)
            }
            if lock.isLocked {
                LockControl(action: unlock)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        .ignoresSafeArea()
        .animation(.default, value: lock.isLocked)
        .lookEnvironment(look, accent: accentColor)
    }
}

private struct SnapshotView: UIViewRepresentable {
    let view: UIView

    func makeUIView(context: Context) -> UIView {
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}

private struct LockControl: View {
    let action: () -> Void

    @Environment(\.look) private var look

    var body: some View {
        Button(action: action) {
            Image(systemName: "lock.fill")
                .font(.system(size: 44, weight: .regular))
                .foregroundStyle(look.label)
                .frame(width: 96, height: 96)
                .background(look.fill, in: .circle)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        // There is no "Unlock" string; the prompt's reason says why the app is locked.
        .accessibilityLabel(L10n.Localizable.LocalAuthorization.reason)
    }
}
