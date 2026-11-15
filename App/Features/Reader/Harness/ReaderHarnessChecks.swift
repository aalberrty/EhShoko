#if DEBUG || HARNESS
import EhFeatures
import UIKit

// The harness's checks of the closing page's slot. Each opens its own readers, takes no
// touch, and writes a report whose last line is `##### done`.
extension ReaderHarnessSession {
    func run(_ check: String) async {
        ReaderHarnessFiles.log("==== check \(check), iOS \(UIDevice.current.systemVersion), \(UIDevice.current.name)")
        switch check {
        case "calls": await checkCalls()
        case "firstpage": await checkFirstPage()
        case "rotation": await checkRotation()
        case "walk": await checkWalk()
        default: ReaderHarnessFiles.log("! unknown check \(check)")
        }
        // The harness's pages are of no use to the next launch.
        await ImagePipeline.cache.clearCache()
        status = "\(check): done"
    }

    private func begin(_ report: String, _ title: String) {
        let device = "iOS \(UIDevice.current.systemVersion), \(UIDevice.current.name)"
        ReaderHarnessFiles.write(["\(title) (\(device))"], to: report)
    }

    // MARK: Recorded calls

    /// The scripted run in every reading mode with the slot off and on, and the two records
    /// compared (`ReaderHarnessComparison`). The records are kept beside the report.
    private func checkCalls() async {
        let report = "calls-report.txt"
        begin(report, "Recorded calls with the closing page's slot off and on")
        var summary: [String] = []
        for mode in ReaderHarnessMode.all where options.modes.isEmpty || options.modes.contains(mode.name) {
            status = "calls: \(mode.name)"
            let off = await record(mode, hasTrailer: false, tag: "off")
            let on = await record(mode, hasTrailer: true, tag: "on")
            let comparison = ReaderHarnessComparison(off: off.lines, on: on.lines, lastPage: mode.setup.pageCount)
            var lines = ["", "##### \(mode.name)"] + comparison.report
            lines += ["notes, slot off:"] + off.notes + ["notes, slot on:"] + on.notes
            summary.append("\(mode.name): \(comparison.verdict.rawValue)")
            if mode.measuresNoise {
                let again = await record(mode, hasTrailer: false, tag: "off2")
                let noise = ReaderHarnessComparison(off: off.lines, on: again.lines, lastPage: mode.setup.pageCount)
                lines += ["", "##### \(mode.name), the slot off twice (how two runs of the same engine differ)"]
                lines += noise.report
                summary.append("\(mode.name), slot off twice: \(noise.verdict.rawValue)")
            }
            ReaderHarnessFiles.append(lines, to: report)
        }
        ReaderHarnessFiles.append(["", "##### summary"] + summary + ["##### done"], to: report)
    }

    private func record(
        _ mode: ReaderHarnessMode, hasTrailer: Bool, tag: String
    ) async -> (lines: [String], notes: [String]) {
        let run = await open(mode.setup.with { $0.hasTrailer = hasTrailer })
        await run.runRoute(animated: mode.isAnimated, opensOnLastPage: mode.opensOnLastPage)
        ReaderHarnessFiles.write(run.recorder.lines, to: "calls-\(mode.name)-\(tag).txt")
        return (run.recorder.lines, run.notes)
    }

    // MARK: First page

    /// How long the first page takes with the slot off and on, in turn, where the slot is out
    /// of reach and where its place is tiled or on screen from the start.
    private func checkFirstPage() async {
        let report = "firstpage-report.txt"
        begin(report, "First page shown, in ms after the reader is made, with the slot off and on")
        let last: (inout ReaderHarnessSetup) -> Void = { $0.startPage = $0.pageCount }
        let cases: [(String, ReaderHarnessSetup)] = [
            ("left to right, opened on page 1", .scripted("first-ltr", direction: .leftToRight)),
            ("left to right, opened on the last page", .scripted("first-ltr-last", direction: .leftToRight).with(last)),
            ("vertical, opened on page 1", .scripted("first-vertical", direction: .vertical)),
            ("vertical, opened on the last page", .scripted("first-vertical-last", direction: .vertical).with(last)),
            (
                "two pages, opened on the last page with the slot beside it",
                ReaderHarnessSetup.scripted(
                    "first-beside", direction: .leftToRight, isDualPage: true, exceptCover: true, isLandscape: true
                ).with(last)
            )
        ]
        for (title, setup) in cases {
            status = "firstpage: \(setup.name)"
            var delays: [Bool: [Double]] = [false: [], true: []]
            var made = 0
            for round in 0..<options.repeatCount {
                // In turn, and the other one first every second round.
                for hasTrailer in round.isMultiple(of: 2) ? [false, true] : [true, false] {
                    let run = await open(setup.with { $0.hasTrailer = hasTrailer })
                    for _ in 0..<600 where run.model.firstPageDelay == nil {
                        try? await Task.sleep(for: .milliseconds(100))
                    }
                    // Where the slot's place is tiled, its content is made after the first page.
                    try? await Task.sleep(for: .milliseconds(700))
                    delays[hasTrailer]?.append((run.model.firstPageDelay ?? -1) * 1_000)
                    if hasTrailer, run.engine?.snapshot?.isTrailerMade == true {
                        made += 1
                    }
                }
            }
            ReaderHarnessFiles.append([
                "", "##### \(title)",
                "off: \(Self.describe(delays[false] ?? []))",
                "on:  \(Self.describe(delays[true] ?? []))",
                "closing page made within 0.7 s of the first page: \(made) of \(options.repeatCount) openings"
            ], to: report)
        }
        ReaderHarnessFiles.append(["##### done"], to: report)
    }

    private static func describe(_ values: [Double]) -> String {
        let sorted = values.sorted()
        guard let least = sorted.first, let most = sorted.last else { return "nothing" }
        let median = sorted.count.isMultiple(of: 2)
            ? (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2 : sorted[sorted.count / 2]
        let list = values.map { String(format: "%.0f", $0) }.joined(separator: " ")
        return String(format: "median %.0f (%.0f to %.0f, n = %d): %@", median, least, most, values.count, list)
    }

    // MARK: Rotation

    /// Turning the screen, and changing the reading direction, at the end of the gallery: the
    /// closing page stays on screen, and the way back returns to where the reader came from.
    private func checkRotation() async {
        let report = ReaderHarnessExpectations(name: "rotation-report.txt", title: "Turning the screen at the end")
        let single = ReaderHarnessSetup.scripted("turn-single", direction: .leftToRight)
        let dual = ReaderHarnessSetup.scripted("turn-dual", direction: .leftToRight, isDualPage: true)
        let dualCover = ReaderHarnessSetup.scripted(
            "turn-dual-cover", direction: .leftToRight, isDualPage: true, exceptCover: true
        )
        let rows: [(String, ReaderHarnessSetup, Bool, Bool)] = [
            ("the closing page alone, to single pages in landscape", single, true, false),
            ("the closing page alone, to two pages with a full last spread", dual, true, false),
            ("the closing page alone, to two pages with page 60 alone", dualCover, true, true),
            ("page 60, to two pages with page 60 alone", dualCover, false, true)
        ]
        for (title, setup, startsOnSlot, isBeside) in rows {
            status = "rotation: \(setup.name)"
            report.section(title)
            let run = await open(setup)
            await run.settle()
            await run.jump(to: 60)
            if startsOnSlot {
                await run.step(1, animated: false)
            }
            report.expect("portrait: " + (startsOnSlot ? "on the closing page" : "on page 60"), run,
                          page: 60, isAtEnd: startsOnSlot, slot: startsOnSlot ? .whole : .none)
            await turn(toLandscape: true)
            await run.settle()
            report.expect("landscape: " + (isBeside ? "page 60 and the closing page" : "the closing page alone"), run,
                          page: 60, isAtEnd: true, slot: isBeside ? .half : .whole)
            await turn(toLandscape: false)
            await run.settle()
            report.expect("portrait again: " + (startsOnSlot ? "the closing page" : "page 60"), run,
                          page: 60, isAtEnd: startsOnSlot, slot: startsOnSlot ? .whole : .none)
        }

        status = "rotation: direction"
        report.section("the strip's closing block, to pages and back")
        let run = await open(.scripted("turn-vertical", direction: .vertical))
        await run.settle()
        await run.jump(to: 60)
        await run.step(1, animated: false)
        report.expect("vertical: on the closing block", run, page: 60, isAtEnd: true, slot: .some)
        run.model.configuration.direction = .leftToRight
        await run.settle()
        report.expect("left to right: the closing page alone", run, page: 60, isAtEnd: true, slot: .whole)
        run.model.configuration.direction = .vertical
        await run.settle()
        report.expect("vertical again: the closing block", run, page: 60, isAtEnd: true, slot: .some)
        if let snapshot = run.engine?.snapshot {
            let end = snapshot.contentSize.height - snapshot.viewSize.height
            report.expect("the strip is at its end", abs(snapshot.contentOffset.y - end) < 1, run.state)
        }
        report.finish()
    }

    // MARK: Behaviour

    /// What the slot does when the reader is told to go somewhere, reloads, or loses the slot.
    private func checkWalk() async {
        let report = ReaderHarnessExpectations(name: "walk-report.txt", title: "The slot's behaviour")
        for direction in [ReaderDirection.leftToRight, .vertical] {
            let name = direction == .vertical ? "vertical" : "left to right"
            // How much of the view the slot covers when the reader is on it.
            let onSlot = direction == .vertical ? ReaderHarnessExpectations.Slot.some : .whole
            status = "walk: \(name)"
            report.section("\(name): steps and jumps")
            let run = await open(.scripted("walk-\(name)", direction: direction))
            await run.settle()
            await run.jump(to: 60)
            report.expect("the last page does not show the slot", run, page: 60, isAtEnd: false, slot: .none)
            report.expect("a step on reaches the slot", await run.step(1, animated: true), run.state)
            report.expect("on the slot", run, page: 60, isAtEnd: true, slot: onSlot)
            report.expect("there is no step past it", await run.step(1, animated: true) == false, run.state)
            report.expect("a step back leaves it", await run.step(-1, animated: true), run.state)
            report.expect("on the last page", run, page: 60, isAtEnd: false, slot: .none)
            await run.step(1, animated: false)
            await run.jump(to: 60)
            report.expect("going to the last page leaves the slot", run, page: 60, isAtEnd: false, slot: .none)

            report.section("\(name): a reload on the slot")
            await run.step(1, animated: false)
            run.model.resetPages()
            await run.settle()
            report.expect("the reader is still on it", run, page: 60, isAtEnd: true, slot: onSlot)

            report.section("\(name): the slot switched off and on")
            run.model.showsClosingSlot = false
            await run.settle()
            report.expect("off: on the last page, nothing kept", run, page: 60, isAtEnd: false, slot: .none)
            report.expect("off: its content is gone", run.engine?.snapshot?.isTrailerMade == false, run.state)
            report.expect("off: there is no step on", await run.step(1, animated: false) == false, run.state)
            run.model.showsClosingSlot = true
            await run.settle()
            report.expect("on again: still on the last page", run, page: 60, isAtEnd: false, slot: .none)
            report.expect("on again: a step on reaches it", await run.step(1, animated: false), run.state)
            report.expect("on the slot", run, page: 60, isAtEnd: true, slot: onSlot)
            let asked = run.recorder.lines.count { $0 == "D makeTrailer" }
            report.expect("its content was asked for once per slot", asked == 2, "asked \(asked) times")
        }

        status = "walk: height"
        report.section("vertical: the content asks for more height")
        let strip = await open(.scripted("walk-height", direction: .vertical))
        await strip.settle()
        await strip.jump(to: 60)
        await strip.step(1, animated: false)
        let least = strip.engine?.snapshot?.trailerFrame?.height ?? 0
        let view = strip.engine?.snapshot?.viewSize.height ?? 0
        report.expect("the block is 70% of the viewport", abs(least - view * 0.7) < 1, "\(least) of \(view)")
        strip.model.isStandInTall = true
        await strip.settle()
        let tall = strip.engine?.snapshot?.trailerFrame?.height ?? 0
        report.expect("the block grew with its content", tall > least + 20, "\(least) -> \(tall)")
        report.expect("the reader is still on it", strip, page: 60, isAtEnd: true, slot: .some)
        strip.model.isStandInTall = false
        await strip.settle()
        let again = strip.engine?.snapshot?.trailerFrame?.height ?? 0
        report.expect("and shrank back", abs(again - least) < 1, "\(tall) -> \(again)")

        status = "walk: late sizes"
        report.section("vertical: opened on the last page before any size is known")
        let late = await open(ReaderHarnessSetup.scripted("walk-late-sizes", direction: .vertical).with {
            $0.startPage = 60
            $0.knowsAspectRatios = false
        })
        await late.settle()
        // Its pages changed height under it; the slot must not have come up with them.
        report.expect("the last page rests on the bottom edge", late, page: 60, isAtEnd: false, slot: .none)
        let slotIsAway = { late.slotOnScreen.height < 1 && !late.model.isAtEnd }
        await turn(toLandscape: true)
        await late.settle()
        report.expect("landscape: the slot is not brought in", slotIsAway(), late.state)
        await turn(toLandscape: false)
        await late.settle()
        report.expect("portrait again: nor here", slotIsAway(), late.state)

        status = "walk: two pages"
        report.section("two pages in one spread: the gallery counts as read on the slot")
        let two = await open(
            .scripted("walk-two", direction: .leftToRight, pageCount: 2, isDualPage: true, isLandscape: true)
        )
        await two.settle()
        report.expect("the spread reports page 1, as it always did", two, page: 1, isAtEnd: false, slot: .none)
        report.expect("a step on reaches the slot", await two.step(1, animated: true), two.state)
        report.expect("the slot reports page 2", two, page: 2, isAtEnd: true, slot: .whole)
        await two.step(-1, animated: true)
        report.expect("back on the spread", two, page: 1, isAtEnd: false, slot: .none)
        await turn(toLandscape: false)
        report.finish()
    }
}

/// A check's report: one line per expectation, `ok` or `FAILED`, with the reader's state.
final class ReaderHarnessExpectations {
    /// How much of the engine's view the slot covers.
    enum Slot {
        case none
        /// Some of it: the strip's block.
        case some
        /// One of two columns: beside the last page.
        case half
        case whole
    }

    private let name: String
    private var failures = 0

    init(name: String, title: String) {
        self.name = name
        let device = "iOS \(UIDevice.current.systemVersion), \(UIDevice.current.name)"
        ReaderHarnessFiles.write(["\(title) (\(device))"], to: name)
    }

    func section(_ title: String) {
        ReaderHarnessFiles.append(["", "##### \(title)"], to: name)
    }

    func expect(_ what: String, _ isMet: Bool, _ detail: String) {
        failures += isMet ? 0 : 1
        ReaderHarnessFiles.append(["\(isMet ? "ok    " : "FAILED") \(what)  [\(detail)]"], to: name)
    }

    /// The reader is on `page`, on the slot or not, and the slot covers that much of the view.
    func expect(_ what: String, _ run: ReaderHarnessRun, page: Int, isAtEnd: Bool, slot: Slot) {
        guard let snapshot = run.engine?.snapshot else {
            expect(what, false, "no engine")
            return
        }
        let covered = run.slotOnScreen
        let view = snapshot.viewSize
        let coversAsExpected = switch slot {
        case .none: covered.width < 1 || covered.height < 1
        case .some: covered.width > view.width - 1 && covered.height > view.height * 0.5
        case .half: abs(covered.width - view.width / 2) < 1 && covered.height > view.height - 1
        case .whole: covered.width > view.width - 1 && covered.height > view.height - 1
        }
        let isMet = snapshot.currentPage == page && snapshot.isTrailerCurrent == isAtEnd
            && run.model.isAtEnd == isAtEnd && coversAsExpected
        expect(what, isMet, run.state)
    }

    func finish() {
        let verdict = failures == 0 ? "every expectation met" : "\(failures) FAILED"
        ReaderHarnessFiles.append(["", verdict, "##### done"], to: name)
    }
}
#endif
