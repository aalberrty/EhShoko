#if DEBUG || HARNESS
import EhCore
import EhFeatures
import Kingfisher
import QuartzCore
import SwiftUI
import UIKit

/// Runs the scripted pairs of `ReaderHarnessRun` one after another, each run with a new
/// gallery and a new engine, and compares the two records of each pair.
@Observable
final class ReaderHarnessScript {
    // Set here and by the checks in `ReaderHarnessScript+Checks.swift`; read by the view.

    /// The run in progress; the view makes its engine.
    var model: ReaderHarnessModel?
    var status = "starting"
    /// Whether the screen is wider than tall, as the view last saw it.
    var isLandscape = false

    @ObservationIgnored private let pairs: [ReaderHarnessPair]
    @ObservationIgnored private let pose: ReaderHarnessRun?
    @ObservationIgnored private let checksRotation: Bool
    @ObservationIgnored var run = ReaderHarnessRun(name: "", hasClosingPage: false)
    @ObservationIgnored private let meter = ReaderHarnessFrameMeter()
    @ObservationIgnored private var summary: [String] = []
    @ObservationIgnored private var hasStarted = false

    init(pairs: [ReaderHarnessPair], pose: ReaderHarnessRun? = nil, checksRotation: Bool = false) {
        self.pairs = pairs
        self.pose = pose
        self.checksRotation = checksRotation
    }

    func start() async {
        guard !hasStarted else { return }
        hasStarted = true
        ReaderHarnessLog.removeAll()
        if let pose {
            await show(pose)
            return
        }
        if checksRotation {
            await checkRotation()
            return
        }
        ReaderHarnessLog.line("matrix: begin, \(pairs.count) pairs, iOS \(UIDevice.current.systemVersion)")
        _ = await perform(ReaderHarnessRun.warmUp)
        for (index, pair) in pairs.enumerated() {
            status = "\(index + 1)/\(pairs.count) \(pair.name)"
            let first = await perform(pair.first)
            let second = await perform(pair.second)
            let comparison = ReaderHarnessComparison(
                first: first.lines, second: second.lines, pageCount: pair.first.pageCount
            )
            ReaderHarnessLog.write(comparison.report.joined(separator: "\n") + "\n", to: "compare-\(pair.name).txt")
            let line = "\(pair.name): \(comparison.verdict.rawValue) | \(pair.first.tag) / \(pair.second.tag):"
                + " first page \(first.firstPage) / \(second.firstPage) ms"
                + " | footprint MB at open \(first.footprintAtOpen) / \(second.footprintAtOpen),"
                + " on the last page \(first.footprintAtLast) / \(second.footprintAtLast)"
                + (second.trailerNote.isEmpty ? "" : " | \(second.trailerNote)")
            summary.append(line)
            ReaderHarnessLog.line("pair " + line)
        }
        await rotate(toLandscape: false)
        ReaderHarnessLog.write(summary.joined(separator: "\n") + "\n", to: "summary.txt")
        status = "done"
        ReaderHarnessLog.line("matrix: done")
    }

    // MARK: One run

    private struct Outcome {
        var lines: [String]
        var firstPage = "?"
        var footprintAtOpen = "?"
        var footprintAtLast = "?"
        /// When the closing page was made, and the late frames of that step.
        var trailerNote = ""
    }

    private func perform(_ run: ReaderHarnessRun) async -> Outcome {
        self.run = run
        await rotate(toLandscape: run.isLandscape)
        // Decoded pages of the last run would count against this one's footprint.
        ImagePipeline.cache.clearMemoryCache()
        try? await Task.sleep(for: .milliseconds(300))
        let recorder = ReaderHarnessRecorder()
        let model = ReaderHarnessModel(run: run, recorder: recorder)
        ReaderHarnessLog.line("run \(run.summary): begin")
        model.markOpened()
        self.model = model
        // The engine exists once its first layout has run.
        for _ in 0..<200 where engine(of: model)?.harnessContent == nil {
            try? await Task.sleep(for: .milliseconds(50))
        }
        var outcome = Outcome(lines: [])
        await script(model, recorder, &outcome)
        recorder.write(tag: run.tag)
        outcome.lines = recorder.lines
        self.model = nil
        model.stop()
        // The last engine goes before the next one is made.
        try? await Task.sleep(for: .milliseconds(400))
        ReaderHarnessLog.line("run \(run.tag): done, \(recorder.lines.count) lines")
        return outcome
    }

    /// Spike S7's script: six turns, a retry, a jump into the middle and turns there, a jump
    /// near the end and turns onto the last page (the mark `last`); then on, past the end,
    /// back twice, on twice, and back to page 1.
    private func script(_ model: ReaderHarnessModel, _ recorder: ReaderHarnessRecorder, _ outcome: inout Outcome) async {
        let count = run.pageCount
        await settle(model, recorder)
        outcome.firstPage = model.firstPageShownAfter.map { String(format: "%.0f", $0) } ?? "?"
        outcome.footprintAtOpen = Self.footprint()
        if let mark = model.trailerMadeAfter {
            // Opened next to it: made after the first image, while the reader opened.
            outcome.trailerNote = "closing page made while opening (\(mark))"
        }
        recorder.add("M open")
        for _ in 0..<min(6, count - 1) {
            _ = await step(model, recorder, by: 1, "advance", &outcome)
        }
        if count >= 7 {
            // Page 7 failed to resolve once.
            model.readerDidRequestRetry(page: 7)
            await settle(model, recorder)
            recorder.add("M retry")
        }
        if count >= 40 {
            await jump(model, recorder, to: 30)
            _ = await step(model, recorder, by: 1, "advance", &outcome)
            _ = await step(model, recorder, by: 1, "advance", &outcome)
            _ = await step(model, recorder, by: -1, "back", &outcome)
            await jump(model, recorder, to: count - 3)
        }
        for _ in 0..<6 where model.currentPage < count {
            guard await step(model, recorder, by: 1, "advance", &outcome) else { break }
        }
        outcome.footprintAtLast = Self.footprint()
        recorder.add("M last")
        // From here the two runs may differ: with the closing page, this step reaches it.
        let reached = await step(model, recorder, by: 1, "advance", &outcome)
        recorder.add("M end reached=\(reached) atEnd=\(model.isAtEnd)")
        let further = await step(model, recorder, by: 1, "advance", &outcome)
        recorder.add("M past end moved=\(further)")
        _ = await step(model, recorder, by: -1, "back", &outcome)
        recorder.add("M back atEnd=\(model.isAtEnd)")
        _ = await step(model, recorder, by: -1, "back", &outcome)
        _ = await step(model, recorder, by: 1, "advance", &outcome)
        _ = await step(model, recorder, by: 1, "advance", &outcome)
        recorder.add("M end again atEnd=\(model.isAtEnd)")
        await jump(model, recorder, to: 1)
        recorder.add("M done")
    }

    private func step(
        _ model: ReaderHarnessModel, _ recorder: ReaderHarnessRecorder, by offset: Int, _ label: String,
        _ outcome: inout Outcome
    ) async -> Bool {
        let madeBefore = model.trailerMadeAfter
        meter.start()
        let moved = engine(of: model)?.harnessStep(by: offset, animated: run.isAnimated) ?? false
        await settle(model, recorder)
        let frames = meter.stop()
        recorder.add("M \(label) moved=\(moved)")
        if madeBefore == nil, let mark = model.trailerMadeAfter {
            outcome.trailerNote = "closing page made after '\(mark)', \(frames)"
            ReaderHarnessLog.line("run \(run.tag): closing page made after '\(mark)'; that step: \(frames)")
        }
        return moved
    }

    private func jump(_ model: ReaderHarnessModel, _ recorder: ReaderHarnessRecorder, to page: Int) async {
        model.proxy.scrollToPage(page)
        await settle(model, recorder)
        recorder.add("M jump \(page)")
    }

    // MARK: Rest

    func engine(of model: ReaderHarnessModel) -> ReaderEngineViewController? {
        model.proxy.harnessEngine
    }

    /// Waits until the reader has come to rest: every page that has a view has its image or
    /// its failure, and over nine polls in a row the scroll position did not move and nothing
    /// was recorded. A poll that arrives late does not count: this Mac stalls the app for
    /// seconds at a time, and a stall is not rest.
    func settle(_ model: ReaderHarnessModel, _ recorder: ReaderHarnessRecorder, limit: Double = 90) async {
        let started = CACurrentMediaTime()
        var lastOffset = engine(of: model)?.harnessContent?.contentOffset
        var lastCount = recorder.lines.count
        var lastPoll = CACurrentMediaTime()
        var quietPolls = 0
        try? await Task.sleep(for: .milliseconds(250))
        while CACurrentMediaTime() - started < limit {
            let now = CACurrentMediaTime()
            let offset = engine(of: model)?.harnessContent?.contentOffset
            let count = recorder.lines.count
            let isOnTime = now - lastPoll < 0.25
            if offset == lastOffset, count == lastCount, isOnTime, pagesAreSettled(model) {
                quietPolls += 1
            } else {
                quietPolls = 0
            }
            lastOffset = offset
            lastCount = count
            lastPoll = now
            if quietPolls >= 9 { return }
            try? await Task.sleep(for: .milliseconds(80))
        }
        ReaderHarnessLog.line("! run \(run.tag): settle gave up after \(Int(limit)) s")
    }

    private func pagesAreSettled(_ model: ReaderHarnessModel) -> Bool {
        guard let pages = engine(of: model)?.harnessContent?.loadedPages else { return true }
        return pages.allSatisfy(model.isSettled)
    }

    // MARK: Orientation

    func rotate(toLandscape landscape: Bool) async {
        guard isLandscape != landscape else { return }
        AppDelegate.setOrientationLock(.unlocked)
        let mask: UIInterfaceOrientationMask = landscape ? .landscapeRight : .portrait
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask))
        }
        for _ in 0..<200 where isLandscape != landscape {
            try? await Task.sleep(for: .milliseconds(50))
        }
        // Let the rotation finish before an engine is made in it.
        try? await Task.sleep(for: .milliseconds(500))
        if isLandscape != landscape {
            ReaderHarnessLog.line("! rotation to \(landscape ? "landscape" : "portrait") did not happen")
        }
    }

    private static func footprint() -> String {
        guard let footprint = MemoryFootprint.current() else { return "?" }
        return String(format: "%.1f", Double(footprint.current) / 1_048_576)
    }
}
#endif
