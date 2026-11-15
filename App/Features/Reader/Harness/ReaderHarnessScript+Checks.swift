#if DEBUG || HARNESS
import EhFeatures
import UIKit

// The scripted runs that are not compared: a reader left on the closing page's stand-in, and
// the rotation check.
extension ReaderHarnessScript {
    /// Opens the pose's reader, steps onto the closing page and leaves it there.
    func show(_ run: ReaderHarnessRun) async {
        self.run = run
        await rotate(toLandscape: run.isLandscape)
        let recorder = ReaderHarnessRecorder()
        let model = ReaderHarnessModel(run: run, recorder: recorder)
        model.isPanelVisible = true
        self.model = model
        for _ in 0..<200 where engine(of: model)?.harnessContent == nil {
            try? await Task.sleep(for: .milliseconds(50))
        }
        await settle(model, recorder)
        if !model.isAtEnd {
            _ = engine(of: model)?.harnessStep(by: 1, animated: true)
            await settle(model, recorder)
        }
        status = run.name
        ReaderHarnessLog.line("pose \(run.name): on the closing page=\(model.isAtEnd), page \(model.currentPage)")
    }

    // MARK: Rotation

    /// Rotating, or switching between the strip and the pager, at the end keeps the reader
    /// where it was: on the closing page, or on the last page when it came from there, also
    /// between a layout where the closing page sits beside the last page and one where it is
    /// alone (spike S7, section 4). Each case logs where the reader is after each change.
    func checkRotation() async {
        let single = ReaderHarnessRun(name: "rotation-single", hasClosingPage: true, startPage: 60)
        var full = single
        full.name = "rotation-two-pages-full"
        full.allowsDualPage = true
        var beside = full
        beside.name = "rotation-two-pages-beside"
        beside.exceptCover = true
        var vertical = single
        vertical.name = "rotation-vertical"
        vertical.direction = .vertical
        for (run, stepsOn) in [(single, true), (full, true), (beside, true), (beside, false)] {
            let model = await open(run)
            if stepsOn {
                _ = engine(of: model)?.harnessStep(by: 1, animated: true)
                await settle(model, model.recorder ?? ReaderHarnessRecorder())
            }
            logRotation(run, "portrait", model)
            await rotate(toLandscape: true)
            await settle(model, model.recorder ?? ReaderHarnessRecorder())
            logRotation(run, "landscape", model)
            await rotate(toLandscape: false)
            await settle(model, model.recorder ?? ReaderHarnessRecorder())
            logRotation(run, "portrait again", model)
            await close(model)
        }
        let model = await open(vertical)
        _ = engine(of: model)?.harnessStep(by: 1, animated: true)
        await settle(model, model.recorder ?? ReaderHarnessRecorder())
        logRotation(vertical, "vertical", model)
        model.configuration.direction = .leftToRight
        await settle(model, model.recorder ?? ReaderHarnessRecorder())
        logRotation(vertical, "paged", model)
        model.configuration.direction = .vertical
        await settle(model, model.recorder ?? ReaderHarnessRecorder())
        logRotation(vertical, "vertical again", model)
        await close(model)
        status = "done"
        ReaderHarnessLog.line("rotation: done")
    }

    private func open(_ run: ReaderHarnessRun) async -> ReaderHarnessModel {
        self.run = run
        await rotate(toLandscape: run.isLandscape)
        let recorder = ReaderHarnessRecorder()
        let model = ReaderHarnessModel(run: run, recorder: recorder)
        self.model = model
        for _ in 0..<200 where engine(of: model)?.harnessContent == nil {
            try? await Task.sleep(for: .milliseconds(50))
        }
        await settle(model, recorder)
        return model
    }

    private func close(_ model: ReaderHarnessModel) async {
        self.model = nil
        model.stop()
        try? await Task.sleep(for: .milliseconds(400))
    }

    /// The page reported, whether the closing page is current, and how much of the screen it
    /// covers.
    private func logRotation(_ run: ReaderHarnessRun, _ moment: String, _ model: ReaderHarnessModel) {
        var covered = 0.0
        if let engine = engine(of: model), let trailer = engine.harnessTrailer, trailer.window != nil {
            let screen = engine.view.bounds
            let frame = trailer.convert(trailer.bounds, to: engine.view).intersection(screen)
            if !frame.isNull, screen.width > 0, screen.height > 0 {
                covered = (frame.width * frame.height) / (screen.width * screen.height)
            }
        }
        ReaderHarnessLog.line(String(
            format: "rotation %@, %@: page %d, closing page %@, covers %.0f%% of the screen",
            run.name, moment, model.currentPage, model.isAtEnd ? "current" : "not current", covered * 100
        ))
    }

}
#endif
