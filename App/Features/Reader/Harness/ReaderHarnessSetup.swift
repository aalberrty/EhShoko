#if DEBUG || HARNESS
import EhFeatures
import Foundation

/// What one reader of the harness opens with. By hand the panel changes the same things; a
/// check (`ReaderHarnessCheck`) opens one reader after another, each from a setup.
struct ReaderHarnessSetup: Equatable {
    /// The run's name in records and reports.
    var name = "by-hand"
    /// Whether a slot for the closing page follows the last page.
    var hasTrailer = true
    var direction = ReaderDirection.vertical
    var allowsDualPage = false
    var exceptCover = false
    var pageCount = 60
    var startPage = 1
    var pageGap: CGFloat = 0
    var knowsAspectRatios = false
    /// Turns the screen before the reader is made.
    var isLandscape = false
    /// Seconds a page takes to resolve its URL, and again to download its image.
    var latency = 0.8
    /// The same delay for every page, so that two runs can be compared. By hand it varies.
    var hasFixedLatency = false
    var showsPanel = true
    /// What fills the closing page's slot.
    var slotContent = ReaderHarnessSlotContent.closingPage
    /// Seconds an image takes to download; `nil`: as long as its URL took to resolve.
    var downloadLatency: Double?
    /// Pages that fail on every attempt; `nil`: every 7th page's URL fails to resolve once
    /// and every 11th page's image fails to load once.
    var failingPages: ReaderHarnessFailingPages?
    /// The look of the page status views and the closing page; `nil`: the app's.
    var look: Look?

    var configuration: ReaderConfiguration {
        ReaderConfiguration(
            direction: direction, allowsDualPage: allowsDualPage, exceptCover: exceptCover, pageGap: pageGap
        )
    }

    /// A reader for a check: short fixed delays, known ratios, no panel in the way.
    static func scripted(
        _ name: String, direction: ReaderDirection, pageCount: Int = 60, isDualPage: Bool = false,
        exceptCover: Bool = false, isLandscape: Bool = false
    ) -> ReaderHarnessSetup {
        ReaderHarnessSetup(
            name: name, direction: direction, allowsDualPage: isDualPage, exceptCover: exceptCover,
            pageCount: pageCount, knowsAspectRatios: true, isLandscape: isLandscape, latency: 0.05,
            hasFixedLatency: true, showsPanel: false
        )
    }

    func with(_ change: (inout ReaderHarnessSetup) -> Void) -> ReaderHarnessSetup {
        var copy = self
        change(&copy)
        return copy
    }
}

/// What fills the closing page's slot in the harness.
enum ReaderHarnessSlotContent: Equatable {
    /// The closing page, on stand-in dependencies (`ReaderClosingHarness`).
    case closingPage
    /// `ReaderHarnessStandIn`, whose height a check changes from outside.
    case standIn
}

/// Pages that fail on every attempt: their URL does not resolve, or their image does not load.
struct ReaderHarnessFailingPages: Equatable {
    var resolution: Set<Int> = []
    var image: Set<Int> = []
}

/// What the harness is asked to do at launch (`-Harness reader`, or `-ReaderHarness YES`):
///
/// | Argument | Meaning |
/// |---|---|
/// | `-ReaderHarnessCheck calls` | Records the scripted run with the closing page's slot off and on in every reading mode and compares the calls (`ReaderHarnessMode`). |
/// | `-ReaderHarnessCheck firstpage` | Times the first page with the slot off and on, in turn. |
/// | `-ReaderHarnessCheck rotation` | Turns the screen and changes the direction at the end of the gallery. |
/// | `-ReaderHarnessCheck walk` | Walks the slot's behaviour: jumps, reloads, the slot switched off, a height change. |
/// | `-ReaderHarnessModes a,b` | Only these modes of `calls`. |
/// | `-ReaderHarnessRepeat <n>` | Openings per case of `firstpage` (default 6). |
/// | `-ReaderHarnessPose alone\|beside\|vertical` | Opens a short gallery on the closing page's slot: alone in the pager, beside the last page (landscape), or as the strip's block. |
/// | `-ReaderHarnessPose status\|status-image` | Opens two pages side by side (landscape): a page that failed to resolve, or whose image failed, beside a page that downloads for two minutes, with a second failed page nearby: the page status views' reason, bytes and "Reload all". |
/// | `-ReaderHarnessLook shelf\|wall\|ledger` | The look of the page status views and the closing page (the app's by default). |
///
/// Reports and records go to `Library/Caches/ReaderHarness/` in the app's container; a report
/// is complete when its last line is `##### done`.
struct ReaderHarnessOptions {
    var check: String?
    var modes: [String] = []
    var repeatCount = 6
    var pose: String?
    var look: Look?

    static var atLaunch: ReaderHarnessOptions {
        let defaults = UserDefaults.standard
        var options = ReaderHarnessOptions()
        options.check = defaults.string(forKey: "ReaderHarnessCheck")
        options.modes = (defaults.string(forKey: "ReaderHarnessModes") ?? "")
            .split(separator: ",").map(String.init)
        let count = defaults.integer(forKey: "ReaderHarnessRepeat")
        if count > 0 {
            options.repeatCount = min(count, 50)
        }
        options.pose = defaults.string(forKey: "ReaderHarnessPose")
        options.look = Look.allCases.first { "\($0)" == defaults.string(forKey: "ReaderHarnessLook") }
        return options
    }

    /// Whether the pose shows the page status views, which stay where the reader opened.
    var posesPageStatus: Bool { pose?.hasPrefix("status") == true }

    /// The reader a pose opens, or `nil` for a name that is not a pose.
    func poseSetup() -> ReaderHarnessSetup? {
        switch pose {
        case "alone": .scripted("pose-alone", direction: .leftToRight, pageCount: 10)
        case "beside":
            .scripted("pose-beside", direction: .leftToRight, pageCount: 9, isDualPage: true, isLandscape: true)
        case "vertical": .scripted("pose-vertical", direction: .vertical, pageCount: 10)
        // The spread of pages 2 and 3 (the cover is alone), the failed page leading.
        case "status":
            Self.statusSetup(startPage: 2, failing: ReaderHarnessFailingPages(resolution: [2, 4]))
        // Pages 6 and 7, the failed image trailing (page 4, a long strip, is too narrow for the card).
        case "status-image":
            Self.statusSetup(startPage: 6, failing: ReaderHarnessFailingPages(resolution: [4], image: [7]))
        default: nil
        }
    }
}

extension ReaderHarnessOptions {
    /// Two pages side by side, whose images take two minutes to download.
    fileprivate static func statusSetup(startPage: Int, failing: ReaderHarnessFailingPages) -> ReaderHarnessSetup {
        ReaderHarnessSetup.scripted(
            "pose-status", direction: .leftToRight, pageCount: 10, isDualPage: true, exceptCover: true, isLandscape: true
        ).with {
            $0.startPage = startPage
            $0.downloadLatency = 120
            $0.failingPages = failing
        }
    }
}

/// One row of the `calls` check: a reading mode, run with the slot off and on.
struct ReaderHarnessMode {
    var setup: ReaderHarnessSetup
    /// Animated page turns, as taps and auto-play make them; otherwise jumps, as the slider's.
    var isAnimated = true
    /// Also runs it a second time with the slot off: how much two runs of the same engine differ.
    var measuresNoise = false
    /// The reader opens on the last page, where the slot's place is tiled from the first
    /// layout on: the run has no turns before the mark `last`, only the opening.
    var opensOnLastPage = false

    var name: String { setup.name }

    static let all: [ReaderHarnessMode] = [
        ReaderHarnessMode(setup: .scripted("ltr", direction: .leftToRight), measuresNoise: true),
        ReaderHarnessMode(setup: .scripted("rtl", direction: .rightToLeft)),
        ReaderHarnessMode(setup: .scripted("single-landscape", direction: .leftToRight, isLandscape: true)),
        ReaderHarnessMode(setup: .scripted("ltr-jumps", direction: .leftToRight), isAnimated: false),
        ReaderHarnessMode(setup: .scripted("vertical", direction: .vertical), measuresNoise: true),
        ReaderHarnessMode(setup: .scripted("vertical-jumps", direction: .vertical), isAnimated: false),
        ReaderHarnessMode(
            setup: ReaderHarnessSetup.scripted("vertical-jumps-unknown-ratios", direction: .vertical).with {
                $0.pageGap = 10
                $0.knowsAspectRatios = false
            },
            isAnimated: false
        ),
        // 60 pages in pairs: the last spread is full, the slot is alone.
        ReaderHarnessMode(
            setup: .scripted("dual-alone", direction: .leftToRight, isDualPage: true, isLandscape: true)
        ),
        // The cover alone leaves page 60 alone: the slot is beside it.
        ReaderHarnessMode(
            setup: .scripted(
                "dual-beside", direction: .leftToRight, isDualPage: true, exceptCover: true, isLandscape: true
            )
        ),
        ReaderHarnessMode(
            setup: .scripted(
                "dual-beside-rtl", direction: .rightToLeft, isDualPage: true, exceptCover: true, isLandscape: true
            )
        ),
        ReaderHarnessMode(
            setup: ReaderHarnessSetup.scripted("ltr-opened-on-last", direction: .leftToRight).with {
                $0.startPage = 60
            },
            opensOnLastPage: true
        ),
        // No size is known when the strip opens, so its last pages change height under it.
        ReaderHarnessMode(
            setup: ReaderHarnessSetup.scripted("vertical-opened-on-last-unknown-ratios", direction: .vertical).with {
                $0.startPage = 60
                $0.knowsAspectRatios = false
            },
            isAnimated: false, opensOnLastPage: true
        ),
        ReaderHarnessMode(setup: .scripted("one-page", direction: .leftToRight, pageCount: 1)),
        ReaderHarnessMode(
            setup: .scripted(
                "three-pages-dual", direction: .leftToRight, pageCount: 3, isDualPage: true, isLandscape: true
            )
        )
    ]
}
#endif
