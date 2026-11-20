import EhModels
import Foundation

/// What the stage plays and how far it has got: a clock over playback time that runs or
/// holds, and the rule that turns a time into the preset and moment to draw.
///
/// Playback time starts at 0 on the first beat `first` plays. Taking turns, each preset's turn
/// passes to the next in the order Shelf, Wall, Ledger; otherwise the stage stays on `first`
/// and starts it again. A turn is eight seconds, or six for a storyboard that skips its first
/// beat (Shelf where the tab bar never tucks away). A pure value: the stage holds it in
/// `@State` and the canvas reads it on any thread.
nonisolated struct StagePlayback: Equatable, Sendable {
    static let order: [DesignStyle] = [.shelf, .wall, .ledger]
    /// About three rounds of the three presets: after this much playing without a touch the
    /// stage stops on the first beat.
    static let idleLimit: TimeInterval = 72
    /// How long a preset takes to dissolve into the next at the end of its turn.
    static let dissolve: TimeInterval = 0.35

    /// The preset at time 0.
    private(set) var first: DesignStyle
    /// Whether the presets take turns; otherwise the stage stays on `first`.
    private(set) var takesTurns: Bool
    /// Whether the tab bar tucks away as a list scrolls on this system, which Shelf's first
    /// beat shows. Fixed for the playback's life, so a time always gives the same picture.
    let tabBarTucks: Bool
    /// When time 0 was, while running.
    private(set) var anchor = Date.distantPast
    /// The time held while stopped; `nil` while running.
    private(set) var held: TimeInterval? = 0
    /// The time of the last touch, from which the idle limit is counted.
    private(set) var lastTouch: TimeInterval = 0

    init(
        first: DesignStyle = .shelf, takesTurns: Bool = true,
        tabBarTucks: Bool = TabAccessoryKind.tabBarMinimizesOnScroll
    ) {
        self.first = first
        self.takesTurns = takesTurns
        self.tabBarTucks = tabBarTucks
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

    func storyboard(_ style: DesignStyle) -> Storyboard {
        Storyboard.of(style, tabBarTucks: tabBarTucks)
    }

    /// The presets in the order they play from time 0.
    var turns: [DesignStyle] {
        guard takesTurns else { return [first] }
        let start = Self.order.firstIndex(of: first) ?? 0
        return Self.order.indices.map { Self.order[(start + $0) % Self.order.count] }
    }

    /// The preset whose turn it is at `time`, and the time its turn began.
    func turn(at time: TimeInterval) -> (style: DesignStyle, began: TimeInterval) {
        let time = max(time, 0)
        let turns = turns
        let cycle = turns.reduce(0) { $0 + storyboard($1).length }
        var began = (time / cycle).rounded(.down) * cycle
        for style in turns {
            let length = storyboard(style).length
            if time < began + length { return (style, began) }
            began += length
        }
        // Only a rounding error at the cycle's very end reaches here.
        return (turns[0], began)
    }

    func style(at time: TimeInterval) -> DesignStyle {
        turn(at: time).style
    }

    /// The preset and the beat (0 to 3) at `time`. A moment a hair past a beat's start counts
    /// as that beat, so a timeline entry that lands on the boundary shows the new one.
    func beat(at time: TimeInterval) -> (style: DesignStyle, beat: Int) {
        let time = max(time, 0) + 0.01
        let (style, began) = turn(at: time)
        let local = storyboard(style).start + time - began
        return (style, min(Int(local / Storyboard.beat), Storyboard.beats - 1))
    }

    /// The scenes at `time`, bottom to top. In its last moments a preset dissolves into what
    /// follows it, drawn underneath at its first beat, so no moment of the cycle is blank and
    /// time 0 is a whole picture to hold.
    func frame(at time: TimeInterval) -> StageFrame {
        let time = max(time, 0)
        let (style, began) = turn(at: time)
        let board = storyboard(style)
        let elapsed = time - began
        let current = scene(style, at: board.start + elapsed)
        let remaining = board.length - elapsed
        guard remaining < Self.dissolve else { return StageFrame(scenes: [current]) }
        let following = self.style(at: began + board.length + 0.001)
        let next = scene(following, at: storyboard(following).start)
        let opacity = Easing.inOut(remaining / Self.dissolve)
        return StageFrame(scenes: [next, scene(style, at: current.time, opacity: opacity)])
    }

    /// `style` at a time of its storyboard.
    func scene(_ style: DesignStyle, at time: TimeInterval, opacity: Double = 1) -> StageScene {
        StageScene(style: style, time: time, opacity: opacity, tabBarTucks: tabBarTucks)
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
        let (style, began) = turn(at: time(at: date))
        let elapsed = time(at: date) - began
        first = style
        takesTurns = true
        set(elapsed, at: date)
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
    /// Which of the preset's storyboards (`Storyboard.of(_:tabBarTucks:)`).
    let tabBarTucks: Bool

    var storyboard: Storyboard { Storyboard.of(style, tabBarTucks: tabBarTucks) }
}
