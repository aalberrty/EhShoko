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
/// | `-HarnessDock YES` | NO | A gallery dock (`ActionDock`) floats over the list, as the shell places it. |
/// | `-HarnessBar YES` | NO | The command bar floats over the list instead, as the shell places it (`command` also works, as in the part harness). |
/// | `-HarnessSpeed <pt/s>` | 2000 | Speed of the scripted scroll. |
/// | `-HarnessCoverLatency <s>` | 0.08 | How long each cover takes to arrive. |
/// | `-HarnessLook <name>` | the slot's design | The look the list is drawn in (`shelf`, `wall`, `ledger`), for a list under another design's colours and type. |
/// | `-HarnessAutoRun YES` | NO | Start the scripted scroll once the first screen has settled. |
/// | `-HarnessRuns <n>` | 1 | With `-HarnessAutoRun`: scroll n times in this one launch. Each run starts from an empty image cache and a list built again with new cover URLs, and has its own `HarnessScroll` interval and its own entry in `result.json`, so one recording (and one save of its trace) stands for n launches. |
/// | `-HarnessExitWhenDone YES` | NO | Quit after writing the result, which ends an `xctrace` recording. |
nonisolated struct ListHarnessOptions: Equatable, Sendable {
    var slot = ListHarnessSlot.shelf
    var galleryCount = 500
    var showsTags = false
    var showsDock = false
    var showsBar = false
    var speed: Double = 2_000
    var coverLatency: Double = 0.08
    /// The look the list is drawn in; `nil` for its own design's.
    var look: DesignStyle?
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
        options.runsAutomatically = defaults.bool(forKey: "HarnessAutoRun")
        options.runs = min(max(defaults.integer(forKey: "HarnessRuns"), 1), 30)
        options.exitsWhenDone = defaults.bool(forKey: "HarnessExitWhenDone")
        return options
    }
}
#endif
