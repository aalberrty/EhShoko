#if DEBUG
import Foundation

/// How a list harness run is set up. From Laboratory every field starts at its default; a
/// launch with `-Harness list` reads them from the launch arguments:
///
/// | Argument | Default | Meaning |
/// |---|---|---|
/// | `-HarnessSlot <name>` | `v3-rows` | The list view under test (`ListHarnessSlot`). |
/// | `-HarnessCount <n>` | 500 | Synthetic galleries. |
/// | `-HarnessTags YES` | NO | Rows show their tags (the slots that have a tag line). |
/// | `-HarnessSpeed <pt/s>` | 2000 | Speed of the scripted scroll. |
/// | `-HarnessCoverLatency <s>` | 0.08 | How long each cover takes to arrive. |
/// | `-HarnessAutoRun YES` | NO | Start the scripted scroll once the first screen has settled. |
/// | `-HarnessExitWhenDone YES` | NO | Quit after writing the result, which ends an `xctrace` recording. |
nonisolated struct ListHarnessOptions: Equatable, Sendable {
    var slot = ListHarnessSlot.v3Rows
    var galleryCount = 500
    var showsTags = false
    var speed: Double = 2_000
    var coverLatency: Double = 0.08
    var runsAutomatically = false
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
        let speed = defaults.double(forKey: "HarnessSpeed")
        if speed > 0 {
            options.speed = speed
        }
        if defaults.object(forKey: "HarnessCoverLatency") != nil {
            options.coverLatency = max(defaults.double(forKey: "HarnessCoverLatency"), 0)
        }
        options.runsAutomatically = defaults.bool(forKey: "HarnessAutoRun")
        options.exitsWhenDone = defaults.bool(forKey: "HarnessExitWhenDone")
        return options
    }
}
#endif
