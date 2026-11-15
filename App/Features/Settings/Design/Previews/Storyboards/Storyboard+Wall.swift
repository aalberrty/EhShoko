import SwiftUI

nonisolated extension Storyboard {
    /// Wall (`tools/anim.py`, `wall`).
    ///
    /// 1. The wall scrolls; two fingers pinch and the covers grow from three columns to two.
    /// 2. A swipe along the bar slides to the next place; its label changes.
    /// 3. A tap on a cover lifts it into the card over its colours; the bar becomes the actions.
    /// 4. The reader opens with one cluster; a drag on it raises the filmstrip.
    static let wall = Storyboard(
        layers: [
            StageLayer(.start(.wall), height: 300, ground: true, origin: CGPoint(x: 50, y: 110), [
                Keyframe(0.4, .down(0)), Keyframe(1, .down(-30)), Keyframe(1.15, .down(-30)),
                Keyframe(1.7, LayerPose(opacity: 0, y: -30, scale: 1.45)),
            ]),
            StageLayer(.list(.wall, top: 6, columns: 2), height: 300, ground: true, origin: CGPoint(x: 50, y: 80), [
                Keyframe(1.25, .zoom(0.7, 0)), Keyframe(1.7, .zoom(1)), Keyframe(2.85, .zoom(1)),
                Keyframe(3.25, .across(-100, 0)),
            ]),
            StageLayer(.list(.wall, top: 6, first: 5, columns: 2), height: 300, ground: true, [
                Keyframe(2.85, .across(100)), Keyframe(3.25, .across(0)),
            ]),
            StageLayer(.bar(.command, place: 0), [Keyframe(2.85, .across(0)), Keyframe(3.1, .across(-8, 0))]),
            StageLayer(.bar(.command, place: 1), [
                Keyframe(2.95, .across(8, 0)), Keyframe(3.25, .across(0)), Keyframe(4.3, .across(0)),
                Keyframe(4.75, .across(0, 0)),
            ]),
            StageLayer(.gallery(.wall), ground: true, origin: CGPoint(x: 26, y: 38), [
                Keyframe(4.25, .zoom(0.3, 0)), Keyframe(4.9, .zoom(1)), Keyframe(6.4, .zoom(1)),
                Keyframe(6.75, .zoom(1, 0)),
            ]),
            StageLayer(.readerPage(.wall), [Keyframe(6.3, .fade(0)), Keyframe(6.7, .fade(1))]),
            StageLayer(.readerControls(.wall), [Keyframe(6.85, .down(6, 0)), Keyframe(7.15, .down(0))]),
            StageLayer(.filmstrip, [Keyframe(7.3, .down(8, 0)), Keyframe(7.55, .down(0))]),
        ],
        fingertips: [
            Fingertip(1.1, 44, 74, to: (26, 50), duration: 0.6),
            Fingertip(1.1, 56, 86, to: (74, 110), duration: 0.6),
            Fingertip(2.7, 64, 141, to: (30, 141), duration: 0.55),
            Fingertip(4.05, 26, 38),
            Fingertip(6.05, 50, 146),
            Fingertip(7.25, 40, 146, to: (60, 146), duration: 0.65),
        ],
        stills: [1.9, 3.6, 5.5, 7.6]
    )
}
