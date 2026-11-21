import SwiftUI

/// The app's root, or a harness in its place when the app is launched to measure one.
///
/// In debug builds, launching with `-Harness part`, `-Harness list`, `-Harness reader`,
/// `-Harness look`, `-Harness dock`, `-Harness previews` or `-Harness rest` shows that harness
/// as the whole app: the shell, its launch sequence and the first screen's requests never start, so nothing
/// else competes with the run being measured. `Scripts/measure.sh` and
/// `Scripts/harness_check.sh` launch it this way. Each harness reads the rest of its arguments
/// itself: `PartHarnessOptions`, `PartHarnessAccount` and `PartHarnessRichPage` (part),
/// `ListHarnessOptions` (list), `ReaderHarnessOptions` (reader).
struct HarnessGate<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        #if DEBUG || HARNESS
        gated.onAppear { HarnessAwake.keepIfMeasuring() }
        #else
        content()
        #endif
    }

    #if DEBUG || HARNESS
    @ViewBuilder
    private var gated: some View {
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
        case .rest:
            // What a device shows between two recordings of a session (`measure.sh rest`).
            HarnessRestView()
        case .translation:
            TranslationHarnessView()
        case nil:
            content()
        }
    }
    #endif
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
    case rest
    case translation

    /// `-Harness <name>`, read once.
    static let atLaunch = UserDefaults.standard.string(forKey: "Harness").flatMap(HarnessRequest.init(rawValue:))
}

/// A launch that measures keeps the screen awake: its runs are scripted, nobody touches the
/// device, and a display that dims or locks halfway ends the recording (and on a phone asks
/// its owner to unlock it again). True for every harness, and for the real app launched with
/// `-HarnessExitAfter`, which quits by itself.
enum HarnessAwake {
    @MainActor
    static func keepIfMeasuring() {
        let quitsByItself = UserDefaults.standard.double(forKey: "HarnessExitAfter") > 0
        guard HarnessRequest.atLaunch != nil || quitsByItself else { return }
        UIApplication.shared.isIdleTimerDisabled = true
    }
}
#endif
