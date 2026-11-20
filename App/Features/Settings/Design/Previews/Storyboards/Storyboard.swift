import EhModels
import SwiftUI

/// Eight seconds of one preset (six where its first beat is skipped), in four beats of two: browse, the design's own way with a
/// list, open a gallery, read (`Design/designs/settings.md`, "The moving preview"). A pure
/// description: which schematic layers to stack, how each moves, and where a fingertip shows
/// a gesture. `tools/anim.py` is the reference: the same layers, the same times.
///
/// One storyboard per preset, in `Storyboard+<Preset>.swift`. Its beats cross five parts, so
/// it has one owner rather than the parts; a part built differently from what its beat shows
/// is corrected here.
nonisolated struct Storyboard: Sendable {
    static let duration: TimeInterval = 8
    static let beat: TimeInterval = 2
    static let beats = 4

    /// Bottom to top.
    let layers: [StageLayer]
    /// Drawn over every layer.
    let fingertips: [Fingertip]
    /// The moment of each beat that stands for it: the still under Reduce Motion, and the
    /// held frame set beside the generator's. One for each of the four beats; a beat that is
    /// not played keeps its still unused.
    let stills: [TimeInterval]
    /// The first beat played. A storyboard whose first beat shows what the system cannot do
    /// starts at the next one, and its turn is that much shorter.
    var firstBeat = 0

    /// The storyboard time its turn starts at.
    var start: TimeInterval { Double(firstBeat) * Self.beat }
    /// How long its turn lasts.
    var length: TimeInterval { Self.duration - start }
    var playedBeats: Range<Int> { firstBeat..<Self.beats }

    /// - Parameter tabBarTucks: whether the tab bar tucks away as a list scrolls on this
    ///   system; where it does not, Shelf skips the beat that shows it.
    static func of(_ style: DesignStyle, tabBarTucks: Bool) -> Storyboard {
        switch style {
        case .shelf: tabBarTucks ? shelf : shelfWithoutTuck
        case .wall: wall
        case .ledger: ledger
        }
    }
}

/// One sheet of shapes on the stage: a schematic drawn on a box 100 units wide and `height`
/// high, moved by its track.
nonisolated struct StageLayer: Sendable {
    let drawing: StageDrawing
    /// The box's height in grid units: 160, or more for a list that scrolls.
    let height: CGFloat
    /// Whether the box is filled with the look's ground under the drawing.
    let fillsGround: Bool
    /// The point a scale is about, in the box's units; its centre when `nil` (CSS's default).
    let origin: CGPoint?
    let track: KeyframeTrack

    init(
        _ drawing: StageDrawing, height: CGFloat = 160, ground: Bool = false, origin: CGPoint? = nil,
        _ keyframes: [Keyframe]
    ) {
        self.drawing = drawing
        self.height = height
        self.fillsGround = ground
        self.origin = origin
        self.track = KeyframeTrack(keyframes)
    }

    var transformOrigin: CGPoint { origin ?? CGPoint(x: SchematicRenderer.gridWidth / 2, y: height / 2) }
}

/// What a layer draws: the still previews' schematics, and the few pieces only the moving
/// preview needs (`StagePieces`).
nonisolated enum StageDrawing: Sendable {
    /// A first screen with its own list, Continue and all.
    case start(DesignStyle)
    /// Shelf's Watched: a large title over rows that differ from Home's.
    case watched
    /// A list's rows from `top`; `first` offsets the stand-in covers, `columns` is Wall's density.
    case list(DesignStyle, top: CGFloat, first: Int = 0, columns: Int = 3)
    /// A list as it is pushed: a centred title over its rows.
    case pushedList(DesignStyle)
    case bar(BarStyle, selected: Int = 0, place: Int = 0, minimised: Bool = false, index: Bool = false)
    case gallery(DesignStyle)
    case readerPage(DesignStyle, shrunk: Bool = false)
    case readerControls(DesignStyle)
    /// Wall's filmstrip, raised by a drag on the reader's cluster.
    case filmstrip
    /// Ledger's Favourite and More, uncovered by a swipe on the row at `y`.
    case swipeActions(y: CGFloat)
    /// Ledger's reader sheet pulled up.
    case openSheet
}

/// A grey fingertip: it lands at `from`, optionally drags to `to`, and lifts, `duration`
/// seconds after `start` (`tools/anim.py`, `tap`).
nonisolated struct Fingertip: Sendable {
    /// Its diameter in grid units: 22 px on the generator's 150 px stage.
    static let diameter: CGFloat = 22 / 1.5

    let start: TimeInterval
    let duration: TimeInterval
    /// Position, size and strength over time: `x`, `y` place its centre.
    let track: KeyframeTrack

    init(_ start: TimeInterval, _ x: CGFloat, _ y: CGFloat, to: (CGFloat, CGFloat)? = nil, duration: TimeInterval = 0.5) {
        self.start = start
        self.duration = duration
        let (endX, endY) = to ?? (x, y)
        track = KeyframeTrack([
            Keyframe(start - 0.01, LayerPose(opacity: 0, x: x, y: y, scale: 0.5)),
            Keyframe(start + 0.12, LayerPose(opacity: 0.6, x: x, y: y, scale: 1)),
            Keyframe(start + duration - 0.12, LayerPose(opacity: 0.6, x: endX, y: endY, scale: 1)),
            Keyframe(start + duration, LayerPose(opacity: 0, x: endX, y: endY, scale: 1.3)),
        ])
    }

    func isShown(at time: TimeInterval) -> Bool {
        time > start - 0.01 && time < start + duration
    }
}
