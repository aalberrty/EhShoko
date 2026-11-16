import SwiftUI

/// The app's root, or a harness in its place when the app is launched to measure one.
///
/// In debug builds, launching with `-Harness part`, `-Harness list`, `-Harness reader`,
/// `-Harness look`, `-Harness dock` or `-Harness previews` shows that harness as the whole
/// app: the shell, its launch sequence and the first screen's requests never start, so nothing
/// else competes with the run being measured. `Scripts/measure.sh` and
/// `Scripts/harness_check.sh` launch it this way. Each harness reads the rest of its arguments
/// itself: `PartHarnessOptions`, `PartHarnessAccount` and `PartHarnessRichPage` (part),
/// `ListHarnessOptions` (list), `ReaderHarnessOptions` (reader).
struct HarnessGate<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        #if DEBUG || HARNESS
        switch HarnessRequest.atLaunch {
        case .part:
            // The part harness: one part of the selectable designs in each of its surroundings
            // (`-Harness part`; `PartHarnessOptions` lists its arguments).
            PartHarnessView()
        case .list:
            ListHarnessView(options: .atLaunch)
        case .reader:
            // The reader harness reads its checks (`-ReaderHarnessCheck calls|firstpage|rotation|walk`,
            // `-ReaderHarnessModes`, `-ReaderHarnessRepeat`, `-ReaderHarnessPose`,
            // `-ReaderHarnessLook`; `ReaderHarnessOptions`). Of the launch actions only
            // `-HarnessExitAfter` means anything here: it ends a memory recording.
            ReaderHarnessView()
                .harnessLaunchActions { _ in }
        case .look:
            LookHarnessView()
        case .dock:
            DockHarnessView()
        case .previews:
            PreviewHarnessView()
        case nil:
            content()
        }
        #else
        content()
        #endif
    }
}

#if DEBUG || HARNESS
/// Which harness the launch arguments ask for.
enum HarnessRequest: String {
    case part
    case list
    case reader
    case look
    case dock
    case previews

    /// `-Harness <name>`, read once.
    static let atLaunch = UserDefaults.standard.string(forKey: "Harness").flatMap(HarnessRequest.init(rawValue:))
}
#endif
