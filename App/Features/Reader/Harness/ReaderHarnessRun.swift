#if DEBUG || HARNESS
import QuartzCore
import UIKit

/// One reader of the harness driven by a script, with its calls recorded: the route through
/// the gallery that two runs share, and the waiting between its steps.
final class ReaderHarnessRun {
    let model: ReaderHarnessModel
    let recorder = ReaderHarnessRecorder()
    /// What the script noted beside the record: the footprint at each mark and the frames of
    /// each step. These differ between any two runs, so they are not part of the record.
    private(set) var notes: [String] = []

    private let meter = ReaderHarnessFrameMeter()

    init(model: ReaderHarnessModel) {
        self.model = model
        // Before the engine exists, so that its first question is on the record.
        model.recorder = recorder
    }

    var engine: ReaderEngineViewController? { model.proxy.inspectedEngine }

    /// Waits for the engine's first layout.
    func waitForEngine() async {
        for _ in 0..<200 where engine?.snapshot == nil {
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    // MARK: The route

    /// Open; six turns; retry page 7; jump to 30; two turns on, one back; jump near the end;
    /// turns on to the last page; **mark `last`**; a turn on (with the slot it reaches it,
    /// without it there is nowhere to go); a turn on; a turn back; a turn back; two turns on;
    /// jump to 1. Animated turns are what taps and auto-play make, the others what the slider
    /// makes. Short galleries skip what they have no pages for.
    func runRoute(animated: Bool) async {
        let count = model.galleryPageCount
        await settle()
        mark("open")
        for _ in 0..<min(6, count - 1) {
            await step(1, animated: animated)
        }
        if count >= 7 {
            // Page 7 failed to resolve once.
            model.readerDidRequestRetry(page: 7)
            await settle()
            recorder.add("M retry")
        }
        if count >= 40 {
            await jump(to: 30)
            await step(1, animated: animated)
            await step(1, animated: animated)
            await step(-1, animated: animated)
            await jump(to: count - 3)
        }
        // On to the last page, however many spreads that takes.
        for _ in 0..<6 where model.currentPage < count {
            guard await step(1, animated: animated) else { break }
        }
        mark("last")

        // From here the two runs may differ.
        let reached = await step(1, animated: animated)
        mark("end reached=\(reached)")
        let further = await step(1, animated: animated)
        mark("past end moved=\(further)")
        await step(-1, animated: animated)
        mark("back")
        await step(-1, animated: animated)
        await step(1, animated: animated)
        await step(1, animated: animated)
        mark("end again")
        await jump(to: 1)
        mark("done")
    }

    /// A mark in the record, and beside it where the reader is and what the app holds.
    func mark(_ label: String) {
        recorder.add("M \(label)")
        let megabytes = MemoryFootprint.current().map { Double($0.current) / 1_048_576 } ?? 0
        notes.append(String(
            format: "  mark %@: page=%d end=%@ footprint=%.1f MB",
            label, model.currentPage, "\(model.isAtEnd)", megabytes
        ))
    }

    /// A page turn forwards or backwards, as a tap in a page-turn zone makes it.
    @discardableResult
    func step(_ offset: Int, animated: Bool) async -> Bool {
        let before = engine?.snapshot
        meter.start()
        let moved = engine?.step(by: offset, animated: animated) ?? false
        await settle()
        let frames = meter.stop()
        let name = offset > 0 ? "advance" : "back"
        recorder.add("M \(name) moved=\(moved)")
        let made = before?.isTrailerMade == false && engine?.snapshot?.isTrailerMade == true
        notes.append("  step \(name) from page \(before?.currentPage ?? 0): \(frames.text)"
            + (made ? "  <- the closing page was made in this step" : ""))
        return moved
    }

    /// A jump without animation, as the slider makes it.
    func jump(to page: Int) async {
        model.proxy.scrollToPage(page)
        await settle()
        recorder.add("M jump \(page)")
    }

    // MARK: Rest

    /// Waits until the reader has come to rest: every page that has a view has its image or
    /// its failure, and over nine polls in a row the scroll position did not move and no call
    /// was recorded. A poll that arrives late does not count: a loaded Mac stalls the app for
    /// seconds at a time, and a stall is not rest.
    func settle(limit: Double = 90) async {
        let started = CACurrentMediaTime()
        var lastOffset = engine?.snapshot?.contentOffset
        var lastCount = recorder.lines.count
        var lastPoll = started
        var quietPolls = 0
        try? await Task.sleep(for: .milliseconds(250))
        while CACurrentMediaTime() - started < limit {
            let now = CACurrentMediaTime()
            let snapshot = engine?.snapshot
            let count = recorder.lines.count
            let isOnTime = now - lastPoll < 0.25
            let pagesAreSettled = snapshot?.loadedPages?.allSatisfy(model.isSettled) ?? true
            if snapshot?.contentOffset == lastOffset, count == lastCount, isOnTime, pagesAreSettled {
                quietPolls += 1
            } else {
                quietPolls = 0
            }
            lastOffset = snapshot?.contentOffset
            lastCount = count
            lastPoll = now
            if quietPolls >= 9 { return }
            try? await Task.sleep(for: .milliseconds(80))
        }
        notes.append("  ! no rest after \(Int(limit)) s")
    }

    // MARK: State

    /// Where the reader is, in one line, for a check's report.
    var state: String {
        guard let snapshot = engine?.snapshot else { return "no engine" }
        let visible = slotOnScreen
        return String(
            format: "page=%d end=%@ made=%@ slot on screen=%.0f×%.0f view=%.0f×%.0f %@ offset=(%.0f,%.0f) zoom=%@",
            snapshot.currentPage, "\(snapshot.isTrailerCurrent)", "\(snapshot.isTrailerMade)",
            visible.width, visible.height, snapshot.viewSize.width, snapshot.viewSize.height,
            snapshot.isPaged ? "paged" : "strip", snapshot.contentOffset.x, snapshot.contentOffset.y,
            snapshot.zoomScales.map { String(format: "%.2f", $0) }.joined(separator: ",")
        )
    }

    /// The part of the slot's view that is inside the engine's view.
    var slotOnScreen: CGSize {
        guard let snapshot = engine?.snapshot, let frame = snapshot.trailerFrame else { return .zero }
        let visible = frame.intersection(CGRect(origin: .zero, size: snapshot.viewSize))
        return visible.isNull ? .zero : visible.size
    }
}
#endif
