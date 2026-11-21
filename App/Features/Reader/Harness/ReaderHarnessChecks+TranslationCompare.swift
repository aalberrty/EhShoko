#if DEBUG || HARNESS
import EhCore
import EhFeatures
import QuartzCore
import UIKit

// The part `compare` of the harness's translation check: the wipe's line, fixed on the screen,
// cuts each page's overlay where it falls on that page, at rest, zoomed in, in the strip, with
// two pages and while a page turns under it; moving it costs a fraction of a frame and makes
// no bitmap.
extension ReaderHarnessSession {
    func checkCompare(_ report: ReaderHarnessExpectations, _ translation: ReaderHarnessTranslation) async {
        let cover: (inout ReaderHarnessSetup) -> Void = { $0.startPage = 2 }
        let setups = [
            ReaderHarnessSetup.scripted("compare-ltr", direction: .leftToRight).with(cover),
            ReaderHarnessSetup.scripted("compare-rtl", direction: .rightToLeft).with(cover),
            ReaderHarnessSetup.scripted("compare-vertical", direction: .vertical).with(cover),
            ReaderHarnessSetup.scripted(
                "compare-dual", direction: .leftToRight, isDualPage: true, exceptCover: true, isLandscape: true
            ).with(cover)
        ]
        for setup in setups {
            status = "translation: \(setup.name)"
            report.section(setup.name)
            let run = await open(setup, translation: translation)
            await run.settle()
            report.expect("the translations are shown", await run.waitForTranslations(), run.translationState)
            for fraction in [0.3, 0.5, 0.72] {
                run.model.proxy.setTranslationDisplay(.compare(fraction: fraction))
                report.expectCut(String(format: "line at %.2f, at rest", fraction), run, fraction: fraction)
            }
            await expectCutWhileTurning(report, run, fraction: 0.72)
            await run.zoom(onPage: run.model.currentPage, at: CGPoint(x: 0.5, y: 0.35))
            report.expectCut("zoomed in", run, fraction: 0.72)
            if setup.direction != .vertical {
                // Panned while zoomed: the page moves under the line.
                if let spread = run.pageView(run.model.currentPage)?.superview?.superview as? UIScrollView {
                    spread.setContentOffset(CGPoint(x: spread.contentOffset.x + 60, y: spread.contentOffset.y), animated: false)
                }
                report.expectCut("zoomed in and panned", run, fraction: 0.72)
            }
            run.model.proxy.setTranslationDisplay(.translated)
            let whole = run.pageViews.compactMap(\.translation.view).allSatisfy { $0.visibleFromX == nil && !$0.clipsToBounds }
            report.expect("back on the translation: every overlay whole", whole, run.translationState)
            report.expectPlaced("and its patches in place", run)
        }
        await checkCompareCost(report, translation)
    }

    /// Samples the cut while a page turns under the line, frame by frame.
    private func expectCutWhileTurning(
        _ report: ReaderHarnessExpectations, _ run: ReaderHarnessRun, fraction: Double
    ) async {
        _ = run.engine?.step(by: 1, animated: true)
        var worst = 0.0
        var samples = 0
        for _ in 0..<24 {
            try? await Task.sleep(for: .milliseconds(12))
            if let error = ReaderHarnessExpectations.cutError(run, fraction: fraction) {
                worst = max(worst, error.worst)
                samples += error.count
            }
        }
        report.expect(
            "while a page turns under the line", samples > 0 && worst < 0.1,
            String(format: "%d overlays sampled, furthest edge %.3f pt off", samples, worst)
        )
        await run.settle()
        await run.waitForTranslations()
        report.expectCut("after the turn", run, fraction: fraction)
    }

    /// What moving the line costs on the main thread, with the commit, and that it reads,
    /// asks for and makes nothing.
    private func checkCompareCost(_ report: ReaderHarnessExpectations, _ translation: ReaderHarnessTranslation) async {
        report.section("Dragging the line")
        let run = await open(
            ReaderHarnessSetup.scripted("compare-cost", direction: .leftToRight).with { $0.startPage = 2 },
            translation: translation
        )
        await run.settle()
        await run.waitForTranslations()
        run.model.proxy.setTranslationDisplay(.compare(fraction: 0.5))
        CATransaction.flush()
        let loads = ReaderTranslationOverlayLoader.loadCount
        let asked = run.recorder.lines.count
        let contents = Self.patchContents(run)
        let before = Self.footprint()
        let meter = ReaderHarnessFrameMeter()
        var costs: [Double] = []
        meter.start()
        for index in 0..<240 {
            // A finger going across and back, a little each frame.
            let phase = Double(index) / 120 * .pi
            let fraction = 0.5 - 0.42 * cos(phase)
            let started = CACurrentMediaTime()
            run.model.proxy.setTranslationDisplay(.compare(fraction: fraction))
            CATransaction.flush()
            costs.append((CACurrentMediaTime() - started) * 1_000)
            try? await Task.sleep(for: .milliseconds(8))
        }
        let frames = meter.stop()
        report.expect("the line still cuts where it is", ReaderHarnessExpectations.cutError(run, fraction: 0.08).map { $0.worst < 0.1 } ?? false, "")
        report.expect(
            "no patch file was read", ReaderTranslationOverlayLoader.loadCount == loads,
            "\(ReaderTranslationOverlayLoader.loadCount - loads) read"
        )
        report.expect("the engine asked for nothing", run.recorder.lines.count == asked, "\(run.recorder.lines.count - asked) calls")
        report.expect(
            "no bitmap was made: the same patch images, no new layer", Self.patchContents(run) == contents,
            "\(contents.count) patch layers"
        )
        report.note("       240 moves, main thread with the commit: \(Self.statistics(costs)) ms; \(frames.text)")
        report.note(String(
            format: "       footprint %.1f MB before the moves, %.1f MB after; load %.1f",
            before, Self.footprint(), Self.loadAverage()
        ))
        let overlays = run.pageViews.compactMap(\.translation.view).map { WeakBox($0) }
        await closeReader()
        try? await Task.sleep(for: .seconds(1))
        let left = overlays.count { $0.object != nil }
        report.expect("the reader closed: every overlay is gone", left == 0, "\(left) of \(overlays.count) left")
    }

    /// Each patch layer's image, by identity, in order: what a new bitmap would change.
    private static func patchContents(_ run: ReaderHarnessRun) -> [ObjectIdentifier] {
        run.pageViews.flatMap { $0.translation.view?.layer.sublayers ?? [] }.compactMap { layer in
            layer.contents.map { ObjectIdentifier($0 as AnyObject) }
        }
    }
}

extension ReaderHarnessExpectations {
    /// Every overlay that shows is cut at the line: its visible part, in the engine's view,
    /// runs from the line (or the image's left edge, if the line is left of the image) to the
    /// image's right edge, and is empty when the line is right of the image.
    func expectCut(_ what: String, _ run: ReaderHarnessRun, fraction: Double) {
        guard let error = Self.cutError(run, fraction: fraction) else {
            expect(what, false, "no engine or no overlay shown: \(run.translationState)")
            return
        }
        expect(
            what, error.count > 0 && error.worst < 0.1,
            String(format: "%d overlays on pages %@, furthest edge %.3f pt off", error.count, error.pages, error.worst)
        )
    }

    static func cutError(_ run: ReaderHarnessRun, fraction: Double) -> (count: Int, worst: Double, pages: String)? {
        guard let host = run.engine?.view else { return nil }
        let line = host.bounds.minX + host.bounds.width * fraction
        var worst = 0.0
        var pages: [Int] = []
        for pageView in run.pageViews where pageView.showsTranslation {
            guard let overlay = pageView.translation.view, overlay.window != nil else { continue }
            let image = pageView.convert(pageView.imageRect, to: host)
            let shown = overlay.convert(overlay.bounds, to: host)
            let start = min(max(line, image.minX), image.maxX)
            worst = max(worst, abs(shown.minX - start), abs(shown.maxX - image.maxX))
            worst = max(worst, abs(shown.minY - image.minY), abs(shown.maxY - image.maxY))
            if !overlay.clipsToBounds { worst = .infinity }
            pages.append(pageView.page)
        }
        guard !pages.isEmpty else { return nil }
        return (pages.count, worst, pages.map(String.init).joined(separator: ","))
    }
}
#endif
