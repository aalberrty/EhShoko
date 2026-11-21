#if DEBUG || HARNESS
import EhCore
import EhFeatures
import os
import QuartzCore
import UIKit

// The measuring parts of the harness's translation check: what an overlay costs, and page
// turns with and without the translation.
extension ReaderHarnessSession {
    // MARK: Cost

    /// What an overlay costs: reading and preparing it off the main actor, and showing it on
    /// the main actor with the commit that follows. The same with the file's own bitmaps,
    /// not prepared for display, to see what the preparation saves.
    func checkCost(_ report: ReaderHarnessExpectations, _ translation: ReaderHarnessTranslation) async {
        report.section("What an overlay costs")
        let run = await open(
            ReaderHarnessSetup.scripted("translation-cost", direction: .leftToRight).with { $0.startPage = 2 },
            translation: translation
        )
        await run.settle()
        guard let host = run.engine?.view else { return }
        let pages = [1, 2, 3, 4, 9, 10, 12, 13]
        for prepares in [true, false, true, false] {
            var loading: [Double] = []
            var showing: [Double] = []
            for page in pages {
                guard let overlay = translation.overlay(at: page) else { continue }
                var started = CACurrentMediaTime()
                let loaded: PageTranslationPatches?
                if prepares {
                    loaded = try? await ReaderTranslationOverlayLoader.load(overlay)
                } else {
                    loaded = try? await overlay.patches()
                }
                guard let patches = loaded else { continue }
                loading.append((CACurrentMediaTime() - started) * 1_000)
                CATransaction.flush()
                let view = ReaderTranslationOverlayView()
                host.addSubview(view)
                started = CACurrentMediaTime()
                view.show(patches)
                view.place(over: host.bounds, displayScale: host.traitCollection.displayScale)
                view.isHidden = false
                CATransaction.flush()
                showing.append((CACurrentMediaTime() - started) * 1_000)
                try? await Task.sleep(for: .milliseconds(100))
                view.removeFromSuperview()
            }
            report.note("       \(prepares ? "prepared for display" : "the file's own bitmaps")"
                + ": read off the main thread \(Self.statistics(loading)) ms;"
                + " shown on the main thread, with the commit \(Self.statistics(showing)) ms")
        }
        report.note(String(format: "       load average %.1f", Self.loadAverage()))

        // What the patches of twenty pages hold while they are loaded and not shown.
        for prepares in [true, false] {
            let before = Self.footprint()
            var held: [PageTranslationPatches] = []
            for page in 1...20 {
                guard let overlay = translation.overlay(at: page) else { continue }
                if prepares, let patches = try? await ReaderTranslationOverlayLoader.load(overlay) {
                    held.append(patches)
                } else if !prepares, let patches = try? await overlay.patches() {
                    held.append(patches)
                }
            }
            try? await Task.sleep(for: .milliseconds(300))
            let bytes = held.flatMap(\.patches).reduce(0) { $0 + $1.image.bytesPerRow * $1.image.height }
            report.note(String(
                format: "       %d pages held, %@: footprint +%.1f MB for %.1f MB of patch bitmaps",
                held.count, prepares ? "prepared for display" : "the file's own bitmaps",
                Self.footprint() - before, Double(bytes) / 1_048_576
            ))
            held = []
            try? await Task.sleep(for: .milliseconds(300))
        }
    }

    // MARK: Paging

    /// Forty animated page turns with and without the translation, in turn: the frames the
    /// main thread delivered late. Each run is also a signpost interval, `TranslationPaging`,
    /// so that a recording of Instruments' Animation Hitches can be read run by run.
    /// `-ReaderHarnessTranslationArm original|translated` runs one of the two only.
    func checkPaging(_ report: ReaderHarnessExpectations, _ translation: ReaderHarnessTranslation) async {
        report.section("Forty page turns, without and with the translation")
        report.note("       frames the main thread delivered, those more than half a frame late, and the longest")
        let signposter = OSSignposter(subsystem: PerformanceSignposts.subsystem, category: PerformanceSignposts.category)
        let only = UserDefaults.standard.string(forKey: "ReaderHarnessTranslationArm")
        for direction in [ReaderDirection.leftToRight, .vertical] {
            let name = direction == .vertical ? "vertical" : "left to right"
            for round in 0..<min(options.repeatCount, 6) {
                for isTranslated in round.isMultiple(of: 2) ? [false, true] : [true, false]
                where only == nil || only == (isTranslated ? "translated" : "original") {
                    status = "translation: paging \(name) \(round + 1)"
                    // No page fails, so the two runs turn the same pages.
                    let setup = ReaderHarnessSetup.scripted("translation-paging", direction: direction).with {
                        $0.failingPages = ReaderHarnessFailingPages()
                    }
                    let run = await open(setup, translation: isTranslated ? translation : nil)
                    await run.settle()
                    let loads = ReaderTranslationOverlayLoader.loadCount
                    var total = ReaderHarnessFrameMeter.Result()
                    let meter = ReaderHarnessFrameMeter()
                    let interval = signposter.beginInterval(
                        "TranslationPaging", "\(name), \(isTranslated ? "translated" : "original")"
                    )
                    for _ in 0..<40 {
                        meter.start()
                        _ = run.engine?.step(by: 1, animated: true)
                        await run.settle()
                        let frames = meter.stop()
                        total.frames += frames.frames
                        total.late += frames.late
                        total.worst = max(total.worst, frames.worst)
                    }
                    signposter.endInterval("TranslationPaging", interval)
                    let read = ReaderTranslationOverlayLoader.loadCount - loads
                    report.note(String(
                        format: "       %@, %@: %@, %d patch files read, on page %d, load %.1f",
                        name, isTranslated ? "translated" : "original  ", total.text, read, run.model.currentPage,
                        Self.loadAverage()
                    ))
                }
            }
        }
    }

    // MARK: Helpers

    static func statistics(_ values: [Double]) -> String {
        let sorted = values.sorted()
        guard let most = sorted.last else { return "nothing" }
        return String(format: "median %.2f, most %.2f (n = %d)", sorted[sorted.count / 2], most, sorted.count)
    }

    static func footprint() -> Double {
        MemoryFootprint.current().map { Double($0.current) / 1_048_576 } ?? 0
    }

    static func loadAverage() -> Double {
        var load = [Double](repeating: 0, count: 1)
        return getloadavg(&load, 1) == 1 ? load[0] : 0
    }
}
#endif
