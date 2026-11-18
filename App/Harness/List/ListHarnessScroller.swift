#if DEBUG || HARNESS
import os
import SwiftUI
import UIKit

/// The scripted scroll: moves the list's scroll view down at a fixed speed, one step per
/// display frame, until the end of the list, as a steady fast drag would.
///
/// It works with any list view (a `List`, a `ScrollView` with lazy content, a collection view)
/// because it drives the `UIScrollView` underneath, found next to `ListHarnessAnchor`. The
/// offset follows the clock, not the frame count, so a late frame jumps further, as under a
/// finger, and every run covers the same distance in the same time.
///
/// It marks the run as the `HarnessScroll` signpost interval (category `Harness`), which
/// `measure.sh` uses to bound the hitches it counts.
///
/// It also counts late display-link frames, for the probes that have nothing better
/// (`SettingsProbe`, the previews harness). That count is no measure of a list: it misses
/// every update that overruns its frame by less than half a frame, which is most of what a
/// list does (it read 0 to 2 ms/s where Instruments counted 113), so the list harness's
/// result and `measure.sh` no longer carry it.
@MainActor
final class ListHarnessScroller: NSObject {
    nonisolated struct Result: Sendable {
        var duration: Double = 0
        var frames = 0
        var distance: Double = 0
        /// Time frames arrived after they were due, summed.
        var hitchTime: Double = 0
        var worstHitch: Double = 0
        var hitches = 0
        /// Frames that took three frame durations or more, after the first screenful.
        var longHitches = 0
        var frameDuration: Double = 0
        var reachedEnd = false
        /// The main thread's CPU time, in seconds, from the first movement to the last, and what
        /// was built and served in that time.
        var mainThreadCPU: Double = 0
        var cellBodies = 0
        var coversServed = 0

        var hitchRatio: Double { duration > 0 ? hitchTime * 1_000 / duration : 0 }
    }

    /// The main thread's clocks at one moment of the run. The scroller runs on the main thread,
    /// so its thread's CPU clock is the main thread's.
    private struct Mark {
        var cpu: UInt64
        var cells: Int
        var served: Int

        static var now: Mark {
            Mark(
                cpu: clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID), cells: ListHarnessCells.value,
                served: ListHarnessURLProtocol.servedCount.withLock { $0 }
            )
        }
    }

    private static let signposter = OSSignposter(subsystem: "app.ehshoko", category: "Harness")

    /// A view inside the list's container; set by `ListHarnessAnchor`.
    weak var anchor: UIView?

    private var link: CADisplayLink?
    private weak var scrollView: UIScrollView?
    private var continuation: CheckedContinuation<Result, Never>?
    private var signpost: OSSignpostIntervalState?
    private var speed = 0.0
    private var startTime: CFTimeInterval?
    private var startOffset: CGFloat = 0
    private var previousTimestamp: CFTimeInterval = 0
    private var previousDuration: CFTimeInterval = 0
    private var endReachedAt: CFTimeInterval?
    private var result = Result()
    /// At the first movement, and at the latest one.
    private var firstMove: Mark?
    private var lastMove: Mark?

    var isRunning: Bool { link != nil }

    /// Runs the scroll from the top and returns what it measured, or `nil` when no scroll view
    /// with room to scroll was found.
    func run(speed: Double) async -> Result? {
        guard !isRunning, let scrollView = findScrollView() else { return nil }
        self.scrollView = scrollView
        self.speed = speed
        result = Result()
        startTime = nil
        endReachedAt = nil
        firstMove = nil
        lastMove = nil
        let top = -scrollView.adjustedContentInset.top
        scrollView.setContentOffset(CGPoint(x: scrollView.contentOffset.x, y: top), animated: false)
        startOffset = top
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
            link.add(to: .main, forMode: .common)
            self.link = link
        }
    }

    func cancel() {
        finish()
    }

    @objc private func tick(_ link: CADisplayLink) {
        guard let scrollView else {
            finish()
            return
        }
        let now = link.timestamp
        if let startTime {
            noteFrame(at: now, scrollView: scrollView)
            let elapsed = now - startTime
            if elapsed > ListHarnessOptions.maximumDuration {
                finish()
                return
            }
        } else {
            startTime = now
            signpost = Self.signposter.beginInterval("HarnessScroll", id: Self.signposter.makeSignpostID())
        }
        previousTimestamp = now
        previousDuration = link.targetTimestamp - link.timestamp
        result.frameDuration = previousDuration
        advance(scrollView, to: now)
    }

    private func noteFrame(at now: CFTimeInterval, scrollView: UIScrollView) {
        result.frames += 1
        let late = (now - previousTimestamp) - previousDuration
        // Display link timestamps jitter by a fraction of a frame; only a missed frame counts.
        guard previousDuration > 0, late > previousDuration * 0.5 else { return }
        result.hitches += 1
        result.hitchTime += late
        result.worstHitch = max(result.worstHitch, late)
        let pastFirstScreen = scrollView.contentOffset.y - startOffset > scrollView.bounds.height
        if pastFirstScreen, now - previousTimestamp >= previousDuration * 3 {
            result.longHitches += 1
        }
    }

    private func advance(_ scrollView: UIScrollView, to now: CFTimeInterval) {
        guard let startTime else { return }
        let inset = scrollView.adjustedContentInset
        let maximum = max(scrollView.contentSize.height + inset.bottom - scrollView.bounds.height, -inset.top)
        let target = min(startOffset + CGFloat(speed * (now - startTime)), maximum)
        if target != scrollView.contentOffset.y {
            let mark = Mark.now
            if firstMove == nil { firstMove = mark }
            lastMove = mark
        }
        scrollView.contentOffset.y = target
        result.distance = Double(target - startOffset)
        guard target >= maximum else {
            endReachedAt = nil
            return
        }
        // Lazy lists grow as they go, so the end only counts once it has held for a moment.
        let reached = endReachedAt ?? now
        endReachedAt = reached
        if now - reached >= ListHarnessOptions.endHold {
            result.reachedEnd = true
            finish()
        }
    }

    private func finish() {
        link?.invalidate()
        link = nil
        if let signpost {
            Self.signposter.endInterval("HarnessScroll", signpost)
            self.signpost = nil
        }
        if let startTime {
            result.duration = previousTimestamp - startTime
        }
        if let firstMove, let lastMove {
            result.mainThreadCPU = Double(lastMove.cpu - firstMove.cpu) / 1e9
            result.cellBodies = lastMove.cells - firstMove.cells
            result.coversServed = lastMove.served - firstMove.served
        }
        continuation?.resume(returning: result)
        continuation = nil
    }

    /// The scroll view of the list: of the scroll views around the anchor with content taller
    /// than themselves, the tallest one under the nearest common ancestor. Going outward one
    /// ancestor at a time keeps the screen below a presented harness out of the search.
    func findScrollView() -> UIScrollView? {
        var container = anchor?.superview
        // Half the list's own width (the anchor's), so a list narrower than its window is
        // found and a strip of thumbnails is not.
        let width = (anchor?.bounds.width ?? 0) / 2
        while let view = container {
            if let found = tallestScrollView(in: view, atLeast: width > 0 ? width : view.bounds.width / 2) {
                return found
            }
            container = view.superview
        }
        return nil
    }

    private func tallestScrollView(in root: UIView, atLeast width: CGFloat) -> UIScrollView? {
        var best: UIScrollView?
        var pending = [root]
        while let view = pending.popLast() {
            if let scrollView = view as? UIScrollView, !scrollView.isHidden,
               scrollView.contentSize.height > scrollView.bounds.height,
               scrollView.bounds.width >= width,
               best.map({ scrollView.contentSize.height > $0.contentSize.height }) ?? true {
                best = scrollView
            }
            pending.append(contentsOf: view.subviews)
        }
        return best
    }
}

/// Marks where the list under test is, so the scroller can find its scroll view. Put it in the
/// background of the slot.
struct ListHarnessAnchor: UIViewRepresentable {
    let scroller: ListHarnessScroller

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        scroller.anchor = view
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        scroller.anchor = uiView
    }
}
#endif
