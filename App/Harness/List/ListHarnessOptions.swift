#if DEBUG || HARNESS
import EhModels
import Foundation

/// How a list harness run is set up. From Laboratory every field starts at its default; a
/// launch with `-Harness list` reads them from the launch arguments:
///
/// | Argument | Default | Meaning |
/// |---|---|---|
/// | `-HarnessSlot <name>` | `shelf` | The list view under test (`ListHarnessSlot`). |
/// | `-HarnessCount <n>` | 500 | Synthetic galleries. |
/// | `-HarnessTags YES` | NO | Rows show their tags (the slots that have a tag line). |
/// | `-HarnessPageSize <n>` | 0 | The ranked slots' list comes in pages of n galleries, each later page under its divider, as Toplists loads them (the site's pages hold 25); 0 is one page. |
/// | `-HarnessDock YES` | NO | A gallery dock (`ActionDock`) floats over the list, as the shell places it. |
/// | `-HarnessBar YES` | NO | The command bar floats over the list instead, as the shell places it (`command` also works, as in the part harness). |
/// | `-HarnessSpeed <pt/s>` | 2000 | Speed of the scripted scroll. |
/// | `-HarnessCoverLatency <s>` | 0.08 | How long each cover takes to arrive. |
/// | `-HarnessLook <name>` | the slot's design | The look the list is drawn in (`shelf`, `wall`, `ledger`), for a list under another design's colours and type. |
/// | `-HarnessWidth <pt>` | 0 | The list's width in points; 0 is the window's. 430 puts a phone's list on an iPad, with a phone's size class. |
/// | `-HarnessCoversReady YES` | NO | Every cover is in memory before a scroll starts, so the scroll does not depend on covers arriving. |
/// | `-HarnessCoresAwake YES` | NO | A thread spins at the highest priority while a list scrolls (`ListHarnessAwake`), which keeps the performance cores at their top speed: the same scroll without the system's power management in the figure. |
/// | `-HarnessAutoRun YES` | NO | Start the scripted scroll once the first screen has settled. |
/// | `-HarnessRuns <n>` | 1 | With `-HarnessAutoRun`: scroll n times in this one launch. Each run starts from an empty image cache and a list built again with new cover URLs, and has its own `HarnessScroll` interval and its own entry in `result.json`, so one recording (and one save of its trace) stands for n launches. |
/// | `-HarnessObserve <s>` | 0 | Instead of the scripted scroll: watch the list for s seconds while a hand scrolls it. Each stretch of movement is a `HarnessScroll` interval and an entry in `result.json`. |
/// | `-HarnessExitWhenDone YES` | NO | Quit after writing the result, which ends an `xctrace` recording. |
///
/// The figures to judge a scroll by are Instruments' (`Scripts/measure.sh`): the kind of each
/// hitch, the time of each frame's update, and the cores the main thread ran on. How long a
/// row takes depends on the speed the system runs the main thread at, which a scroll that
/// leaves it idle between rows does not get much of: compare runs in the same state.
nonisolated struct ListHarnessOptions: Equatable, Sendable {
    var slot = ListHarnessSlot.shelf
    var galleryCount = 500
    var showsTags = false
    /// The galleries in each page of a ranked slot's list; 0 for one page.
    var pageSize = 0
    var showsDock = false
    var showsBar = false
    var speed: Double = 2_000
    var coverLatency: Double = 0.08
    /// The look the list is drawn in; `nil` for its own design's.
    var look: DesignStyle?
    /// The list's width in points; 0 for the window's.
    var width = 0
    var hasCoversReady = false
    var keepsCoresAwake = false
    /// Seconds the list is watched while a hand scrolls it; 0 for the scripted scroll.
    var observedSeconds: Double = 0
    var runsAutomatically = false
    /// How many scripted scrolls an automatic run makes in one launch.
    var runs = 1
    var exitsWhenDone = false

    /// Seconds between the list's first appearance and the automatic run: the first screen's
    /// covers arrive and decode in that time, so the run measures scrolling, not the first frame.
    static let settleDelay = 2.0
    /// The run stops this long after reaching the end, or after `maximumDuration` in any case.
    static let endHold = 0.5
    static let maximumDuration = 180.0

    static let `default` = ListHarnessOptions()

    static var atLaunch: ListHarnessOptions {
        let defaults = UserDefaults.standard
        var options = ListHarnessOptions()
        if let slot = defaults.string(forKey: "HarnessSlot").flatMap(ListHarnessSlot.init(rawValue:)) {
            options.slot = slot
        }
        let count = defaults.integer(forKey: "HarnessCount")
        if count > 0 {
            options.galleryCount = min(count, 5_000)
        }
        options.showsTags = defaults.bool(forKey: "HarnessTags")
        options.pageSize = min(max(defaults.integer(forKey: "HarnessPageSize"), 0), 5_000)
        options.showsDock = defaults.bool(forKey: "HarnessDock")
        options.showsBar = defaults.bool(forKey: "HarnessBar") || defaults.string(forKey: "HarnessBar") == "command"
        let speed = defaults.double(forKey: "HarnessSpeed")
        if speed > 0 {
            options.speed = speed
        }
        if defaults.object(forKey: "HarnessCoverLatency") != nil {
            options.coverLatency = max(defaults.double(forKey: "HarnessCoverLatency"), 0)
        }
        options.look = defaults.string(forKey: "HarnessLook").flatMap(DesignStyle.init(rawValue:))
        options.width = max(defaults.integer(forKey: "HarnessWidth"), 0)
        options.hasCoversReady = defaults.bool(forKey: "HarnessCoversReady")
        options.keepsCoresAwake = defaults.bool(forKey: "HarnessCoresAwake")
        options.observedSeconds = min(max(defaults.double(forKey: "HarnessObserve"), 0), 600)
        options.runsAutomatically = defaults.bool(forKey: "HarnessAutoRun")
        options.runs = min(max(defaults.integer(forKey: "HarnessRuns"), 1), 30)
        options.exitsWhenDone = defaults.bool(forKey: "HarnessExitWhenDone")
        return options
    }
}
#endif
