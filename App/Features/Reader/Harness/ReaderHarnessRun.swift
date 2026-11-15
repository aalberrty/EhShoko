#if DEBUG || HARNESS
import EhFeatures
import Foundation

/// One scripted run of the reader harness: the gallery, the reading mode and the script.
///
/// Launching with `-Harness reader -ReaderHarnessScript matrix` runs every pair of
/// `ReaderHarnessRun.matrix` one after another in the running app, each run with a new engine,
/// and compares the two runs of each pair (`ReaderHarnessComparison`). `-ReaderHarnessScript
/// <name>` runs only the pairs whose name starts with `<name>` (`ltr`, `vertical`, `dual`…).
/// Records, comparisons and a summary go to `Library/Caches/ReaderHarness` in the app's
/// container; `summary.txt` is written last, when everything is done.
nonisolated struct ReaderHarnessRun: Equatable, Sendable {
    /// The pair it belongs to, as in `compare-<name>.txt`.
    var name: String
    var hasClosingPage: Bool
    var direction: ReaderDirection = .leftToRight
    var allowsDualPage = false
    var exceptCover = false
    var pageCount = 60
    var startPage = 1
    var pageGap: CGFloat = 0
    var knowsAspectRatios = true
    /// Seconds a page takes to resolve, and again to download: fixed, so two runs compare.
    var latency = 0.05
    /// The run starts in landscape (two pages need it).
    var isLandscape = false
    /// Page turns are animated, as taps and auto-play make them; otherwise they jump, as the
    /// slider does.
    var isAnimated = true
    /// Tells apart a second run without the closing page, made to see the noise.
    var repeatNumber = 1

    var tag: String {
        "\(name)-\(hasClosingPage ? "on" : "off")" + (repeatNumber > 1 ? "\(repeatNumber)" : "")
    }

    var configuration: ReaderConfiguration {
        ReaderConfiguration(
            direction: direction, allowsDualPage: allowsDualPage, exceptCover: exceptCover, pageGap: pageGap
        )
    }

    var summary: String {
        "\(tag): \(direction) dual=\(allowsDualPage) cover=\(exceptCover) pages=\(pageCount) gap=\(Int(pageGap)) "
            + "ratios=\(knowsAspectRatios) landscape=\(isLandscape) animated=\(isAnimated)"
    }
}

/// Two runs whose records are compared: without the closing page, then with it (or, for the
/// noise, twice without it).
nonisolated struct ReaderHarnessPair: Sendable {
    var name: String
    var first: ReaderHarnessRun
    var second: ReaderHarnessRun

    /// The closing page off, then on.
    static func slot(_ name: String, _ run: ReaderHarnessRun) -> ReaderHarnessPair {
        var off = run
        off.name = name
        off.hasClosingPage = false
        var on = off
        on.hasClosingPage = true
        return ReaderHarnessPair(name: name, first: off, second: on)
    }

    /// The closing page off twice: what two runs of today's engine differ by.
    static func noise(_ name: String, _ run: ReaderHarnessRun) -> ReaderHarnessPair {
        var off = run
        off.name = name
        off.hasClosingPage = false
        var again = off
        again.repeatNumber = 2
        return ReaderHarnessPair(name: name + "-noise", first: off, second: again)
    }
}

extension ReaderHarnessRun {
    private static let base = ReaderHarnessRun(name: "", hasClosingPage: false)

    private static func with(_ change: (inout ReaderHarnessRun) -> Void) -> ReaderHarnessRun {
        var run = base
        change(&run)
        return run
    }

    /// The runs of spike S7's table. Not among them: a gallery of two pages in the two-page
    /// layout, whose one spread reports page 1, so that only the closing page's slot reports
    /// page 2 and the two runs must differ before the last page (the layout's tests cover it).
    static let matrix: [ReaderHarnessPair] = [
        .slot("ltr", with { $0.direction = .leftToRight }),
        .noise("ltr", with { $0.direction = .leftToRight }),
        .slot("rtl", with { $0.direction = .rightToLeft }),
        .slot("single-landscape", with { $0.direction = .leftToRight; $0.isLandscape = true }),
        .slot("ltr-jumps", with { $0.direction = .leftToRight; $0.isAnimated = false }),
        .slot("vertical", with { $0.direction = .vertical }),
        .noise("vertical", with { $0.direction = .vertical }),
        .slot("vertical-jumps", with { $0.direction = .vertical; $0.isAnimated = false }),
        .slot("vertical-jumps-unknown-ratios", with {
            $0.direction = .vertical
            $0.isAnimated = false
            $0.pageGap = 10
            $0.knowsAspectRatios = false
        }),
        .slot("dual-alone", with { $0.allowsDualPage = true; $0.isLandscape = true }),
        .slot("dual-beside", with { $0.allowsDualPage = true; $0.exceptCover = true; $0.isLandscape = true }),
        .slot("dual-beside-rtl", with {
            $0.direction = .rightToLeft
            $0.allowsDualPage = true
            $0.exceptCover = true
            $0.isLandscape = true
        }),
        .slot("one-page", with { $0.pageCount = 1 }),
        .slot("three-pages-dual", with { $0.pageCount = 3; $0.allowsDualPage = true; $0.isLandscape = true })
    ]

    /// `-ReaderHarnessPose alone|beside|vertical`: a reader on the closing page's stand-in, left
    /// on screen to look at and to touch. `beside` is the two-page layout in landscape, where
    /// the stand-in shares the screen with the last page.
    static var poseAtLaunch: ReaderHarnessRun? {
        switch UserDefaults.standard.string(forKey: "ReaderHarnessPose") {
        case "alone": with { $0.name = "pose-alone"; $0.hasClosingPage = true; $0.startPage = 60 }
        case "vertical":
            with { $0.name = "pose-vertical"; $0.hasClosingPage = true; $0.direction = .vertical; $0.startPage = 60 }
        case "beside":
            with {
                $0.name = "pose-beside"
                $0.hasClosingPage = true
                $0.allowsDualPage = true
                $0.exceptCover = true
                $0.isLandscape = true
                $0.startPage = 60
            }
        default: nil
        }
    }

    /// The pairs the launch arguments ask for, or `nil` when they ask for no scripted run.
    static var requestedAtLaunch: [ReaderHarnessPair]? {
        guard let name = UserDefaults.standard.string(forKey: "ReaderHarnessScript"), !name.isEmpty else {
            return nil
        }
        return name == "matrix" ? matrix : matrix.filter { $0.name.hasPrefix(name) }
    }
}
#endif
