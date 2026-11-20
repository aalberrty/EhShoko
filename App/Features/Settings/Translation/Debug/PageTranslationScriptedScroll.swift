#if DEBUG
import os
import SwiftUI

extension View {
    /// With `-PageTranslationScroll <n>` in a debug build, scrolls this screen from the top to
    /// the end `n` times, ten seconds after it appears (so that whatever opened it has
    /// gone quiet, such as the device tools reading the accessibility tree), with the list harness's scripted
    /// scroller (a steady drag at 1,200 pt/s), and logs one line a run (category
    /// `PageTranslationScroll`): late display-link frames and the main thread's CPU time.
    /// Instruments cannot record hitches on a simulator, so this is how a selection screen's
    /// scroll is checked there, as `SettingsProbe` checks the Settings page.
    func pageTranslationScriptedScroll() -> some View {
        modifier(ScriptedScrollModifier())
    }
}

private struct ScriptedScrollModifier: ViewModifier {
    private static let runs = UserDefaults.standard.integer(forKey: "PageTranslationScroll")
    private static let logger = Logger(subsystem: "app.ehshoko", category: "PageTranslationScroll")

    @State private var scroller = Self.runs > 0 ? ListHarnessScroller() : nil

    func body(content: Content) -> some View {
        if let scroller {
            content
                .background { ListHarnessAnchor(scroller: scroller) }
                .task { await run(scroller) }
        } else {
            content
        }
    }

    private func run(_ scroller: ListHarnessScroller) async {
        try? await Task.sleep(for: .seconds(10))
        for index in 1...Self.runs {
            guard !Task.isCancelled, let result = await scroller.run(speed: 1_200) else { return }
            Self.logger.notice("""
                Run \(index, privacy: .public): \(result.duration * 1_000, format: .fixed(precision: 0), privacy: .public) ms, \
                \(Int(result.distance), privacy: .public) pt, \(result.frames, privacy: .public) frames of \
                \(result.frameDuration * 1_000, format: .fixed(precision: 1), privacy: .public) ms, \
                \(result.hitches, privacy: .public) late (\(result.hitchTime * 1_000, format: .fixed(precision: 1), privacy: .public) ms, \
                worst \(result.worstHitch * 1_000, format: .fixed(precision: 1), privacy: .public) ms, \
                \(result.hitchRatio, format: .fixed(precision: 1), privacy: .public) ms/s), \
                \(result.longHitches, privacy: .public) of three frames or more, main thread \
                \(result.mainThreadCPU * 1_000, format: .fixed(precision: 0), privacy: .public) ms of CPU, \
                reached the end: \(result.reachedEnd, privacy: .public)
                """)
            try? await Task.sleep(for: .seconds(1))
        }
    }
}
#endif
