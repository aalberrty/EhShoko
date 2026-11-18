#if DEBUG || HARNESS
import os
import UIKit

/// Watches the list while a hand scrolls it (`-HarnessObserve <s>`): every stretch of
/// movement is a `HarnessScroll` interval, as the scripted scroll's run is, with what the
/// main thread did in it, so that Instruments' hitches of a real scroll can be bounded and set
/// beside the script's.
///
/// A stretch starts with the first change of the content offset and ends when the offset has
/// rested for a quarter of a second (a finger between two flicks does not end it).
@MainActor
final class ListHarnessObserver: NSObject {
    nonisolated struct Stretch: Sendable {
        var duration: Double
        var distance: Double
        var frames: Int
        var frameDuration: Double
        var mainThreadCPU: Double
        var cellBodies: Int
        /// Of the body runs, those for a cell built before; and the cells standing built
        /// beyond where the list had got to when the stretch ended (`ListHarnessCells.Tally`).
        var cellsAgain: Int
        var cellsAhead: Int
        var coversServed: Int
    }

    private struct Mark {
        let time: CFTimeInterval
        let offset: CGFloat
        let frames: Int
        let cpu: UInt64
        let cells: Int
        let served: Int
    }

    private static let signposter = OSSignposter(subsystem: "app.ehshoko", category: "Harness")
    private static let rest = 0.25

    private let scroller: ListHarnessScroller
    private let stretchEnded: (Stretch) -> Void
    private var link: CADisplayLink?
    private weak var scrollView: UIScrollView?
    private var signpost: OSSignpostIntervalState?
    private var start: Mark?
    private var lastOffset: CGFloat = 0
    private var lastMove: CFTimeInterval = 0
    private var distance: CGFloat = 0
    private var frames = 0
    private var frameDuration: CFTimeInterval = 0

    /// - Parameter scroller: the harness's scroller, whose anchor says where the list is.
    init(scroller: ListHarnessScroller, stretchEnded: @escaping (Stretch) -> Void) {
        self.scroller = scroller
        self.stretchEnded = stretchEnded
    }

    func begin() {
        guard link == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    /// Stops watching; a stretch still open ends here.
    func end() {
        link?.invalidate()
        link = nil
        endStretch()
    }

    @objc private func tick(_ link: CADisplayLink) {
        if scrollView == nil {
            scrollView = scroller.findScrollView()
            lastOffset = scrollView?.contentOffset.y ?? 0
        }
        guard let scrollView else { return }
        frames += 1
        frameDuration = link.targetTimestamp - link.timestamp
        let now = link.timestamp
        let offset = scrollView.contentOffset.y
        if abs(offset - lastOffset) > 0.5 {
            if start == nil {
                signpost = Self.signposter.beginInterval("HarnessScroll", id: Self.signposter.makeSignpostID())
                distance = 0
                start = Mark(
                    time: now, offset: lastOffset, frames: frames, cpu: clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID),
                    cells: ListHarnessCells.value, served: ListHarnessURLProtocol.servedCount.withLock { $0 }
                )
            }
            distance += abs(offset - lastOffset)
            lastOffset = offset
            lastMove = now
        } else if start != nil, now - lastMove > Self.rest {
            endStretch()
        }
    }

    private func endStretch() {
        guard let start else { return }
        self.start = nil
        if let signpost {
            Self.signposter.endInterval("HarnessScroll", signpost)
            self.signpost = nil
        }
        let bodies = ListHarnessCells.value - start.cells
        let tally = ListHarnessCells.tally(last: bodies)
        stretchEnded(Stretch(
            duration: lastMove - start.time, distance: Double(distance), frames: frames - start.frames,
            frameDuration: frameDuration,
            mainThreadCPU: Double(clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID) - start.cpu) / 1e9,
            cellBodies: bodies, cellsAgain: tally.again, cellsAhead: tally.ahead,
            coversServed: ListHarnessURLProtocol.servedCount.withLock { $0 } - start.served
        ))
    }
}
#endif
