import SwiftUI

nonisolated extension Storyboard {
    /// Shelf (`tools/anim.py`, `shelf`).
    ///
    /// 1. Home scrolls; the tab bar tucks into one button with Continue beside it.
    /// 2. A tap brings the bar back; a tap on Watched moves the selection and the list changes.
    /// 3. A tap on a cover zooms it into the gallery page; the tab bar gives way to the dock.
    /// 4. A tap on Continue opens the reader; the top bar and the bottom panel arrive.
    static let shelf = Storyboard(
        layers: [
            StageLayer(.start(.shelf), height: 300, ground: true, [
                Keyframe(0.5, .down(0)), Keyframe(1.7, .down(-60)), Keyframe(2.9, .down(-60)),
                Keyframe(3.3, .down(-60, 0)),
            ]),
            StageLayer(.watched, height: 220, ground: true, [Keyframe(2.9, .fade(0)), Keyframe(3.3, .fade(1))]),
            StageLayer(.bar(.tabs, selected: 0), [
                Keyframe(0.9, .fade(1)), Keyframe(1.3, .fade(0)), Keyframe(2.35, .fade(0)),
                Keyframe(2.6, .fade(1)), Keyframe(2.95, .fade(1)), Keyframe(3.15, .fade(0)),
            ]),
            StageLayer(.bar(.tabs, minimised: true), [
                Keyframe(0.9, .fade(0)), Keyframe(1.3, .fade(1)), Keyframe(2.35, .fade(1)), Keyframe(2.6, .fade(0)),
            ]),
            StageLayer(.bar(.tabs, selected: 1), [
                Keyframe(2.95, .fade(0)), Keyframe(3.15, .fade(1)), Keyframe(4.3, .fade(1)), Keyframe(4.7, .fade(0)),
            ]),
            StageLayer(.gallery(.shelf), ground: true, origin: CGPoint(x: 16, y: 40), [
                Keyframe(4.25, .zoom(0.2, 0)), Keyframe(4.9, .zoom(1)), Keyframe(6.4, .zoom(1)),
                Keyframe(6.75, .zoom(1, 0)),
            ]),
            StageLayer(.readerPage(.shelf), [Keyframe(6.3, .fade(0)), Keyframe(6.7, .fade(1))]),
            StageLayer(.readerControls(.shelf), [Keyframe(6.9, .down(6, 0)), Keyframe(7.3, .down(0))]),
        ],
        fingertips: [
            Fingertip(2.2, 15, 141),
            Fingertip(2.8, 31, 141),
            Fingertip(4.05, 16, 40),
            Fingertip(6.05, 50, 146),
        ],
        stills: [1.8, 3.6, 5.5, 7.6]
    )
}
