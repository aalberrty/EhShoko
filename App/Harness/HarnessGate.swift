import SwiftUI

/// The app's root, or a harness in its place when the app is launched to measure one.
///
/// In debug builds, launching with `-Harness list`, `-Harness reader`, `-Harness look` or `-Harness dock` shows that harness as
/// the whole app: the shell, its launch sequence and the first screen's requests never start,
/// so nothing else competes with the run being measured. `Scripts/measure.sh`
/// launches it this way; `ListHarnessOptions` lists the other arguments.
struct HarnessGate<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        #if DEBUG
        switch HarnessRequest.atLaunch {
        case .list:
            ListHarnessView(options: .atLaunch)
        case .reader:
            ReaderHarnessView()
        case .look:
            LookHarnessView()
        case .dock:
            DockHarnessView()
        case nil:
            content()
        }
        #else
        content()
        #endif
    }
}

#if DEBUG
/// Which harness the launch arguments ask for.
enum HarnessRequest: String {
    case list
    case reader
    case look
    case dock

    /// `-Harness <name>`, read once.
    static let atLaunch = UserDefaults.standard.string(forKey: "Harness").flatMap(HarnessRequest.init(rawValue:))
}
#endif
