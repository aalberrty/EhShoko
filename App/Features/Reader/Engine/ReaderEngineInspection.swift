#if DEBUG || HARNESS
import EhFeatures
import UIKit

/// What the engine decides by itself, which no data-source or delegate call shows. The reader
/// harness records these beside the calls, so that a run with the trailer can be compared with
/// one without it. Nothing is reported unless a probe is attached, which the reader never does.
enum ReaderEngineProbeEvent {
    /// The page ranges handed to the prefetcher after the tiling changed.
    case prefetch(visible: ClosedRange<Int>?, loaded: ClosedRange<Int>?)
    /// A page view was given a page, to decode for `request`.
    case configure(page: Int, request: ReaderDecodeRequest)
    /// A page view is about to be told its page's content: the `pageState(at:)` call that
    /// follows is that view's, not one of the prefetcher's passes.
    case pageContent(page: Int)
}

/// The engine at one moment, for the reader harness's scripts and checks.
struct ReaderEngineSnapshot {
    var currentPage: Int
    var isTrailerCurrent: Bool
    /// Whether the trailer's content has been asked for.
    var isTrailerMade: Bool
    /// The trailer's frame in the engine's view while it is in a scroll view.
    var trailerFrame: CGRect?
    var isPaged: Bool
    var viewSize: CGSize
    var contentOffset: CGPoint
    var contentSize: CGSize
    /// The strip's zoom, or the zoom of every spread that has a view, from left to right.
    var zoomScales: [CGFloat]
    var loadedPages: ClosedRange<Int>?
}

extension ReaderEngineViewController {
    var snapshot: ReaderEngineSnapshot? {
        guard let content else { return nil }
        let spreads = content.subviews.compactMap { $0 as? ReaderSpreadView }.sorted { $0.frame.minX < $1.frame.minX }
        return ReaderEngineSnapshot(
            currentPage: currentPage,
            isTrailerCurrent: isTrailerCurrent,
            isTrailerMade: trailer != nil,
            trailerFrame: trailer.flatMap { $0.superview == nil ? nil : $0.convert($0.bounds, to: view) },
            isPaged: content is ReaderPagedView,
            viewSize: view.bounds.size,
            contentOffset: content.contentOffset,
            contentSize: content.contentSize,
            zoomScales: content is ReaderPagedView ? spreads.map(\.zoomScale) : [content.zoomScale],
            loadedPages: content.loadedPages
        )
    }

    /// A step forwards or backwards, as a tap in a page-turn zone makes it.
    func step(by offset: Int, animated: Bool) -> Bool {
        content?.advance(by: offset, animated: animated) ?? false
    }
}
#endif
