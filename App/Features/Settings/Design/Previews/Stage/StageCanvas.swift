import EhModels
import SwiftUI

/// The stage while it plays: one canvas in a timeline of at most 30 frames a second, drawn
/// off the main thread. Each frame the main actor works out only the time; the storyboard is
/// read and the shapes are drawn where the asynchronous canvas runs. When the playback holds,
/// the timeline is paused and nothing runs at all.
///
/// Compared by value, so an update of the stage around it that changes neither the playback
/// nor the palettes leaves the canvas alone.
struct StageCanvas: View, Equatable {
    let playback: StagePlayback
    let palettes: StagePalettes

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !playback.isRunning)) { timeline in
            let frame = playback.frame(at: playback.time(at: timeline.date))
            Canvas(rendersAsynchronously: true, renderer: StageRenderer.renderer(frame, palettes: palettes))
        }
    }
}

/// The stage when nothing may play (Reduce Motion, or animated images turned off): one still
/// per beat, paged by the stage. `position` counts pages; between two whole pages the canvas
/// dissolves one still into the next, so a page turn animated on `position` is a cross-fade
/// inside the one canvas.
struct StageStill: View, Animatable {
    var position: Double
    let playback: StagePlayback
    let palettes: StagePalettes

    var animatableData: Double {
        get { position }
        set { position = newValue }
    }

    var body: some View {
        Canvas(
            rendersAsynchronously: true,
            renderer: StageRenderer.renderer(StagePager.frame(at: position, of: playback), palettes: palettes)
        )
    }
}

/// The stills of the pager: one per beat a preset plays, the beats' moments of its
/// storyboard. Taking turns, the pages run through the three presets; staying on one, through
/// its own.
nonisolated enum StagePager {
    static func pages(of playback: StagePlayback) -> [StageBeat] {
        playback.turns.flatMap { style in
            playback.storyboard(style).playedBeats.map { StageBeat(style: style, beat: $0) }
        }
    }

    static func scene(_ page: Int, of playback: StagePlayback, opacity: Double = 1) -> StageScene {
        let beat = beat(page, of: playback)
        return playback.scene(beat.style, at: playback.storyboard(beat.style).stills[beat.beat], opacity: opacity)
    }

    static func frame(at position: Double, of playback: StagePlayback) -> StageFrame {
        let lower = position.rounded(.down)
        let progress = position - lower
        let below = scene(Int(lower), of: playback)
        guard progress > 0.001 else { return StageFrame(scenes: [below]) }
        return StageFrame(scenes: [below, scene(Int(lower) + 1, of: playback, opacity: progress)])
    }

    /// The preset and beat of the page nearest `position`.
    static func beat(at position: Double, of playback: StagePlayback) -> StageBeat {
        beat(Int(position.rounded()), of: playback)
    }

    /// The page that shows `beat`, or the first.
    static func page(of beat: StageBeat, in playback: StagePlayback) -> Int {
        pages(of: playback).firstIndex(of: beat) ?? 0
    }

    private static func beat(_ page: Int, of playback: StagePlayback) -> StageBeat {
        let pages = pages(of: playback)
        let count = pages.count
        return pages[(page % count + count) % count]
    }
}

/// The preset and beat (0 to 3) the stage shows, for its name, caption and marks.
nonisolated struct StageBeat: Equatable, Sendable {
    let style: DesignStyle
    let beat: Int
}

/// A timeline entry at every beat while the playback runs, and one entry while it holds: the
/// name, caption, marks and tiles under the stage change at most every two seconds, so they
/// are not drawn again with every frame of the canvas.
nonisolated struct StageBeatSchedule: TimelineSchedule {
    /// When storyboard time 0 was, while running.
    let anchor: Date?

    func entries(from startDate: Date, mode: TimelineScheduleMode) -> Entries {
        Entries(upcoming: startDate, anchor: anchor)
    }

    struct Entries: Sequence, IteratorProtocol {
        var upcoming: Date?
        let anchor: Date?

        mutating func next() -> Date? {
            guard let current = upcoming else { return nil }
            if let anchor {
                let beats = (current.timeIntervalSince(anchor) / Storyboard.beat).rounded(.down) + 1
                upcoming = anchor.addingTimeInterval(beats * Storyboard.beat)
            } else {
                upcoming = nil
            }
            return current
        }
    }
}
