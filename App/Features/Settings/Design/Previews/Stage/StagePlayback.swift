import EhModels
import Foundation

/// What the stage plays and how far it has got: a clock over storyboard time that runs or
/// holds, and the rule that turns a time into the preset and moment to draw.
///
/// Storyboard time starts at 0 on the first beat of `first`. Taking turns, every eight seconds
/// pass to the next preset in the order Shelf, Wall, Ledger; otherwise the stage stays on
/// `first` and starts it again. A pure value: the stage holds it in `@State` and the canvas
/// reads it on any thread.
nonisolated struct StagePlayback: Equatable, Sendable {
    static let order: [DesignStyle] = [.shelf, .wall, .ledger]
    /// Three rounds of the three presets: after this much playing without a touch the stage
    /// stops on the first beat.
    static let idleLimit: TimeInterval = 72
    /// How long a preset takes to dissolve into the next at the end of its eight seconds.
    static let dissolve: TimeInterval = 0.35

    /// The preset at time 0.
    private(set) var first: DesignStyle
    /// Whether the presets take turns; otherwise the stage stays on `first`.
    private(set) var takesTurns: Bool
    /// When time 0 was, while running.
    private(set) var anchor = Date.distantPast
    /// The time held while stopped; `nil` while running.
    private(set) var held: TimeInterval? = 0
    /// The time of the last touch, from which the idle limit is counted.
    private(set) var lastTouch: TimeInterval = 0

    init(first: DesignStyle = .shelf, takesTurns: Bool = true) {
        self.first = first
        self.takesTurns = takesTurns
    }

    var isRunning: Bool { held == nil }

    func time(at date: Date) -> TimeInterval {
        held ?? max(date.timeIntervalSince(anchor), 0)
    }

    /// The date the stage stops by itself, while it runs.
    var idleStop: Date? {
        isRunning ? anchor.addingTimeInterval(lastTouch + Self.idleLimit) : nil
    }

    // MARK: What to draw

    func style(at time: TimeInterval) -> DesignStyle {
        guard takesTurns else { return first }
        let start = Self.order.firstIndex(of: first) ?? 0
        let turn = Int((max(time, 0) / Storyboard.duration).rounded(.down))
        return Self.order[(start + turn) % Self.order.count]
    }

    /// The preset and the beat (0 to 3) at `time`. A moment a hair past a beat's start counts
    /// as that beat, so a timeline entry that lands on the boundary shows the new one.
    func beat(at time: TimeInterval) -> (style: DesignStyle, beat: Int) {
        let time = time + 0.01
        let local = time.truncatingRemainder(dividingBy: Storyboard.duration)
        return (style(at: time), min(Int(local / Storyboard.beat), Storyboard.beats - 1))
    }

    /// The scenes at `time`, bottom to top. In its last moments a preset dissolves into what
    /// follows it, drawn underneath at its first beat, so no moment of the cycle is blank and
    /// time 0 is a whole picture to hold.
    func frame(at time: TimeInterval) -> StageFrame {
        let local = max(time, 0).truncatingRemainder(dividingBy: Storyboard.duration)
        let current = StageScene(style: style(at: time), time: local, opacity: 1)
        let remaining = Storyboard.duration - local
        guard remaining < Self.dissolve else { return StageFrame(scenes: [current]) }
        let next = StageScene(style: style(at: time + remaining + 0.001), time: 0, opacity: 1)
        let opacity = Easing.inOut(remaining / Self.dissolve)
        return StageFrame(scenes: [next, StageScene(style: current.style, time: local, opacity: opacity)])
    }

    // MARK: Changes

    mutating func stop(at date: Date) {
        guard held == nil else { return }
        held = time(at: date)
    }

    mutating func run(at date: Date) {
        guard let held else { return }
        anchor = date.addingTimeInterval(-held)
        self.held = nil
    }

    /// Plays `style` from its first beat, staying on it or taking turns from it.
    mutating func show(_ style: DesignStyle, takesTurns: Bool, at date: Date) {
        first = style
        self.takesTurns = takesTurns
        set(0, at: date)
    }

    /// Takes turns again from the preset now showing, at the same moment of it.
    mutating func takeTurns(at date: Date) {
        let time = time(at: date)
        first = style(at: time)
        takesTurns = true
        set(time.truncatingRemainder(dividingBy: Storyboard.duration), at: date)
    }

    /// Counts the idle limit from now.
    mutating func touch(at date: Date) {
        lastTouch = time(at: date)
    }

    /// Back to the first beat, held: where the stage rests after the idle limit.
    mutating func rewind() {
        held = 0
        lastTouch = 0
    }

    private mutating func set(_ time: TimeInterval, at date: Date) {
        if held == nil {
            anchor = date.addingTimeInterval(-time)
        } else {
            held = time
        }
        lastTouch = time
    }
}

/// What the canvas draws at one moment: one or two presets, each at its own time.
nonisolated struct StageFrame: Equatable, Sendable {
    /// Bottom to top.
    var scenes: [StageScene]
}

nonisolated struct StageScene: Equatable, Sendable {
    let style: DesignStyle
    /// Seconds into its storyboard.
    let time: TimeInterval
    let opacity: Double
}
