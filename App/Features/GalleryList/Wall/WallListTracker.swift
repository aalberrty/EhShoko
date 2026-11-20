import EhFeatures
import SwiftUI

/// Where the wall is scrolled to, kept outside SwiftUI's state: the offset changes on every
/// frame of a scroll and nothing must be invalidated by it. A plain class held as `@State`.
final class WallListTracker {
    /// The row a density change kept in place, for the next change to keep again.
    struct Kept {
        let anchor: Int
        /// The offset that change asked for.
        let offset: CGFloat
        /// The layout it was made in: a later change in another one starts afresh.
        let map: WallGridMap
        /// The scroll view has been seen at `offset`.
        var isSettled = false
    }

    /// Where the scroll view is, as it reports it.
    struct Place: Equatable {
        /// How far the content is scrolled, 0 at its top under the bars: the value
        /// `ScrollPosition.scrollTo(y:)` takes.
        var offset: CGFloat = 0
        /// How much of the scroll view the bars above it cover.
        var topInset: CGFloat = 0
        /// How high the scroll view is.
        var height: CGFloat = 0

        init() {}

        init(_ geometry: ScrollGeometry) {
            offset = geometry.contentOffset.y + geometry.contentInsets.top
            topInset = geometry.contentInsets.top
            height = geometry.containerSize.height
        }
    }

    private(set) var place = Place()
    /// Where the first row of covers starts in the content.
    var cellsTop: CGFloat = 0
    /// The wall has appeared and not disappeared since: not under a pushed screen, nor in a
    /// tab that is not shown.
    var isOnScreen = false
    private var kept: Kept?

    var offset: CGFloat { place.offset }

    func moved(to place: Place) {
        self.place = place
        if let kept, abs(place.offset - kept.offset) < 1 {
            self.kept?.isSettled = true
        }
    }

    /// The row an earlier change kept, while the wall is laid out as `map` and still where
    /// that change left it (or on its way there). It is judged when asked for, not when the
    /// offset is reported: iOS 18 reports the offset before the change once more after the
    /// new one, and a row forgotten for that slipped at the next change.
    func kept(in map: WallGridMap) -> Kept? {
        guard let kept, kept.map == map, !kept.isSettled || abs(offset - kept.offset) < 1 else { return nil }
        return kept
    }

    func keep(_ anchor: Int?, at offset: CGFloat, in map: WallGridMap) {
        kept = anchor.map { Kept(anchor: $0, offset: offset, map: map) }
    }

    /// Someone scrolls, or the entries are others: the row at the top is another.
    func forget() {
        kept = nil
    }

    /// What a numbered list draws: the pages near where the scroll view was last seen and,
    /// after a density change, those near where it was sent, until it has been seen there.
    /// The scroll view reports its new offset only after the wall is drawn in its new layout,
    /// and what is drawn then must already be what the new offset shows.
    func drawn(of spans: ListPageSpans) -> ListPageSpans.Drawn {
        var tops = [top(at: place.offset)]
        if let kept, !kept.isSettled {
            tops.append(top(at: kept.offset))
        }
        return spans.drawn(onScreensAt: tops, height: place.height)
    }

    /// The scroll view's top edge when it is at `offset`, from the first row of covers.
    private func top(at offset: CGFloat) -> CGFloat {
        offset - place.topInset - cellsTop
    }
}

/// The wall as a whole for a moment after a density change made at once: a little larger or
/// smaller, as the covers were, and faded. One transform on one layer, in place of an
/// animation of every cell, which a lazy grid cannot do (`spikes/S1.md`).
struct WallDensityCue: Equatable {
    var scale: CGFloat = 1
    var opacity: Double = 1

    static let rest = WallDensityCue()

    /// - Parameter moves: false under Reduce Motion, where the change is a cross-fade.
    init(from old: WallGridLayout, to new: WallGridLayout, moves: Bool) {
        scale = moves ? min(max(old.pitch / new.pitch, 0.94), 1.06) : 1
        opacity = 0.55
    }

    private init() {}
}
