#if DEBUG || HARNESS
import SwiftUI

/// The translation harness (`-Harness translation`): the app's page translation service run
/// over a folder of pages in the container, writing stage times, memory and thermal state as
/// JSON (`TranslationHarnessOptions` lists the arguments).
///
/// The screen is black with one dim line that moves a little every second, because a run
/// keeps the display awake for minutes and a still, bright screen left image retention on a
/// phone once. When the run ends the idle timer is let go, so the phone locks itself.
struct TranslationHarnessView: View {
    @State private var model = TranslationHarnessModel()

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            Text(verbatim: model.line)
                .font(.footnote.monospaced())
                .foregroundStyle(Color(white: model.isDone ? 0.2 : 0.3))
                .lineLimit(3)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .frame(maxWidth: 420)
                .offset(Self.drift(at: timeline.date.timeIntervalSinceReferenceDate))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.black)
        .ignoresSafeArea()
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .preferredColorScheme(.dark)
        .task { await model.run() }
    }

    /// Two slow sweeps of unequal periods, so the line never rests on the same pixels.
    private static func drift(at seconds: Double) -> CGSize {
        func sweep(_ period: Double) -> Double {
            let phase = seconds.truncatingRemainder(dividingBy: period) / period
            return (phase < 0.5 ? phase * 2 : 2 - phase * 2) * 2 - 1
        }
        return CGSize(width: 60 * sweep(97), height: 220 * sweep(61))
    }
}

@MainActor @Observable
final class TranslationHarnessModel {
    private(set) var line = "Translation harness · starting"
    private(set) var isDone = false
    @ObservationIgnored private var hasStarted = false

    func run() async {
        guard !hasStarted else { return }
        hasStarted = true
        let options = TranslationHarnessOptions.atLaunch
        let run = TranslationHarnessRun(options: options) { [weak self] line in self?.line = line }
        let last = await Task.detached(priority: .userInitiated) { await run.run() }.value
        line = last
        isDone = true
        // The run is over: the phone may dim and lock as usual.
        UIApplication.shared.isIdleTimerDisabled = false
        if options.exitsWhenDone { exit(0) }
    }
}
#endif
