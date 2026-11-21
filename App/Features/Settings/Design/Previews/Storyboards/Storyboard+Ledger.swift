import SwiftUI

nonisolated extension Storyboard {
    /// Ledger (`tools/anim.py`, `ledger`).
    ///
    /// 1. The Index; a tap on Front Page pushes its dense rows, which scroll.
    /// 2. A swipe on a row uncovers Favourite and More, then closes.
    /// 3. A tap on a row zooms its cover into the document page with its dock.
    /// 4. The reader opens with its sheet at rest; a drag pulls it up and the page settles above.
    static let ledger = Storyboard(
        layers: [
            StageLayer(.start(.ledger), ground: true, [Keyframe(1, .across(0)), Keyframe(1.5, .across(-30, 0))]),
            StageLayer(.pushedList(.ledger), height: 260, ground: true, [
                Keyframe(1, .across(100)), Keyframe(1.5, .across(0)), Keyframe(1.75, .across(0)),
                Keyframe(2.35, .down(-22)),
            ]),
            StageLayer(.swipeActions(y: 43.5), [
                Keyframe(2.9, .across(40, 0)), Keyframe(3.3, .across(0)), Keyframe(3.75, .across(0)),
                Keyframe(4.05, .across(40, 0)),
            ]),
            StageLayer(.bar(.command, index: true), [Keyframe(1, .fade(1)), Keyframe(1.4, .fade(0))]),
            StageLayer(.bar(.command), [
                Keyframe(1.1, .fade(0)), Keyframe(1.5, .fade(1)), Keyframe(4.3, .fade(1)), Keyframe(4.75, .fade(0)),
            ]),
            StageLayer(.gallery(.ledger), ground: true, origin: CGPoint(x: 11, y: 30), [
                Keyframe(4.25, .zoom(0.22, 0)), Keyframe(4.9, .zoom(1)), Keyframe(6.4, .zoom(1)),
                Keyframe(6.75, .zoom(1, 0)),
            ]),
            StageLayer(.readerPage(.ledger), [
                Keyframe(6.3, .fade(0)), Keyframe(6.7, .fade(1)), Keyframe(7.3, .fade(1)), Keyframe(7.6, .fade(0)),
            ]),
            StageLayer(.readerPage(.ledger, shrunk: true), [Keyframe(7.3, .fade(0)), Keyframe(7.6, .fade(1))]),
            StageLayer(.readerControls(.ledger), [
                Keyframe(6.8, .down(8, 0)), Keyframe(7.1, .down(0)), Keyframe(7.3, .down(0)), Keyframe(7.45, .down(0, 0)),
            ]),
            StageLayer(.openSheet, [Keyframe(7.25, .down(96)), Keyframe(7.6, .down(0))]),
        ],
        fingertips: [
            Fingertip(0.8, 40, 57),
            Fingertip(2.8, 84, 54, to: (52, 54), duration: 0.55),
            Fingertip(4.1, 11, 30),
            Fingertip(6.05, 50, 146),
            Fingertip(7.15, 50, 126, to: (50, 70), duration: 0.5),
        ],
        stills: [1.7, 3.5, 5.5, 7.6]
    )
}
