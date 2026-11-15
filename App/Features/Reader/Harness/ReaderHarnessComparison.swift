#if DEBUG || HARNESS
import Foundation

/// Compares the records of two scripted runs (`ReaderHarnessRecorder`), the first without the
/// closing page and the second with it, as spike S7 did (`spikes/S7.md`, section 2).
///
/// Everything before the mark `last` (the reader has arrived on the last page) must be the
/// same, read the way the spike read it:
/// - in order, what the engine decides: the pages it needs and releases, the current page,
///   retries, what it hands its prefetcher and the page views it fills;
/// - as sets, what finishes when it finishes: images loaded with their decoded size, images
///   failed, `aspectRatio` calls, `pageState` asked by page views;
/// - counted, not compared: `pageState` asked by the prefetcher's own passes, which run
///   whenever a download finishes and differ between two runs of today's engine.
///
/// What comes after the mark is listed step by step, since with the closing page the next
/// step reaches it.
nonisolated struct ReaderHarnessComparison {
    enum Verdict: String {
        case identical = "identical"
        /// An animated scroll of the strip passes through tile states between its start and
        /// its end; which of them a frame lands on is a matter of timing. Per step, the page
        /// views filled and the state it comes to rest in are the same.
        case identicalPerStep = "identical per step (tile states on the way differ)"
        /// Beside the closing page the last page has half the screen: its decode size, and
        /// nothing else, differs.
        case identicalButLastPageSize = "identical but for the last page's decode size"
        case different = "DIFFERENT"
    }

    private(set) var report: [String] = []
    private(set) var verdict = Verdict.different

    private static let pageEvents = ["E needs", "E release", "E page", "E retry"]
    private static let trailerCalls = ["D hasTrailer", "D makeTrailer", "E trailer"]
    private static let trace = ["T prefetch", "T configure"]

    init(first: [String], second: [String], pageCount: Int) {
        let (firstHead, firstTail) = Self.split(first)
        let (secondHead, secondTail) = Self.split(second)
        report.append("first: \(first.count) lines, \(firstHead.count) before 'last'; second: \(second.count) lines, \(secondHead.count) before 'last'")
        report.append("Before the last page is reached (first / second):")
        let isSame = compareHeads(firstHead, secondHead)
        if isSame.inOrder && isSame.sets && isSame.trace {
            verdict = .identical
        } else if isSame.inOrder && isSame.sets && isSame.tracePerStep {
            verdict = .identicalPerStep
        } else {
            let lastPage = ["T configure \(pageCount) ", "E loaded \(pageCount) "]
            let drop = { (lines: [String]) in lines.filter { line in !lastPage.contains { line.hasPrefix($0) } } }
            var without = ReaderHarnessComparison(empty: ())
            let again = without.compareHeads(drop(firstHead), drop(secondHead))
            if again.inOrder && again.sets && (again.trace || again.tracePerStep) {
                verdict = .identicalButLastPageSize
                let only = Self.difference(Self.only(firstHead, lastPage), Self.only(secondHead, lastPage))
                report.append("  without page \(pageCount)'s decode lines everything is the same; they differ by \(only)")
            }
        }
        reportCounts(firstHead, secondHead)
        reportTail(firstTail, secondTail)
        report.append("RESULT: \(verdict.rawValue)")
    }

    private init(empty: Void) {}

    // MARK: Before the mark

    private struct Sameness {
        var inOrder: Bool
        var sets: Bool
        var trace: Bool
        var tracePerStep: Bool
    }

    private mutating func compareHeads(_ first: [String], _ second: [String]) -> Sameness {
        let events = check("page events in order (needs, release, current page, retry)",
                           Self.only(first, Self.pageEvents), Self.only(second, Self.pageEvents))
        let marks = check("marks (the script took the same steps)", Self.only(first, ["M "]), Self.only(second, ["M "]))
        let failed = check("images failed, sorted",
                           Self.only(first, ["E failed"]).sorted(), Self.only(second, ["E failed"]).sorted())
        let views = check("pageState asked by page views, sorted",
                          Self.only(first, ["T content"]).sorted(), Self.only(second, ["T content"]).sorted())
        let loaded = check("images loaded, as a set (page and decoded size)",
                           Set(Self.only(first, ["E loaded"])).sorted(), Set(Self.only(second, ["E loaded"])).sorted())
        let aspect = check("aspectRatio calls, sorted",
                           Self.only(first, ["D aspect"]).sorted(), Self.only(second, ["D aspect"]).sorted())
        let trace = check("engine trace in order (prefetch window inputs, page views filled)",
                          Self.only(first, Self.trace), Self.only(second, Self.trace))
        var perStep = trace
        if !trace {
            perStep = check("engine trace per step (page views filled, and the state it rests in)",
                            Self.steps(first), Self.steps(second))
        }
        let strip = { (lines: [String]) in lines.filter { !Self.has($0, Self.trailerCalls) } }
        let exact = strip(first) == strip(second)
        report.append("  \(exact ? "SAME" : "diff")  every call in order, the trailer's calls set aside: "
            + "\(strip(first).count) / \(strip(second).count)" + (exact ? "" : " (the prefetcher's passes need not match)"))
        return Sameness(
            inOrder: events && marks, sets: failed && views && loaded && aspect, trace: trace, tracePerStep: perStep
        )
    }

    private mutating func check(_ name: String, _ first: [String], _ second: [String]) -> Bool {
        let isSame = first == second
        let detail = isSame ? "" : "  <-- " + Self.firstDifference(first, second) + "; " + Self.difference(first, second)
        report.append("  \(isSame ? "SAME" : "DIFF")  \(name): \(first.count) / \(second.count)\(detail)")
        return isSame
    }

    private mutating func reportCounts(_ first: [String], _ second: [String]) {
        let passes = { (lines: [String]) in
            Self.only(lines, ["D pageState"]).count - Self.only(lines, ["T content"]).count
        }
        report.append("  pageState asked by the prefetcher's passes (varies with download timing): "
            + "\(passes(first)) / \(passes(second))")
        let early = Self.only(second, Self.trailerCalls).filter { $0 != "D hasTrailer" }
        report.append("  trailer calls before the last page (second): " + (early.isEmpty ? "none" : early.joined(separator: ", ")))
    }

    // MARK: After the mark

    private mutating func reportTail(_ first: [String], _ second: [String]) {
        report.append("From the last page on (page calls compared, the trailer's calls listed):")
        let strip = { (lines: [String]) in lines.filter { !Self.has($0, Self.trailerCalls) && !$0.hasPrefix("D pageState") } }
        for (one, two) in zip(Self.segments(first), Self.segments(second)) {
            let calls = Self.only(two.lines, Self.trailerCalls).filter { $0 != "D hasTrailer" }
            let same = strip(one.lines).sorted() == strip(two.lines).sorted()
            report.append("  '\(one.mark)' / '\(two.mark)': "
                + (same ? "same page calls" : Self.difference(strip(one.lines), strip(two.lines)))
                + (calls.isEmpty ? "" : "; trailer calls \(calls)"))
        }
    }

    // MARK: Helpers

    private static func split(_ lines: [String]) -> (head: [String], tail: [String]) {
        guard let index = lines.firstIndex(where: { $0.hasPrefix("M last") }) else { return (lines, []) }
        return (Array(lines[..<index]), Array(lines[index...]))
    }

    private static func has(_ line: String, _ prefixes: [String]) -> Bool {
        prefixes.contains { line.hasPrefix($0) }
    }

    private static func only(_ lines: [String], _ prefixes: [String]) -> [String] {
        lines.filter { has($0, prefixes) }
    }

    /// Lines grouped by the script step they belong to: a step ends with its `M` line.
    private static func segments(_ lines: [String]) -> [(mark: String, lines: [String])] {
        var groups: [(mark: String, lines: [String])] = []
        var current: [String] = []
        for line in lines {
            if line.hasPrefix("M ") {
                groups.append((line, current))
                current = []
            } else {
                current.append(line)
            }
        }
        if !current.isEmpty {
            groups.append(("M (tail)", current))
        }
        return groups
    }

    /// Per step: the page views filled, sorted, and the last prefetch line, which is the state
    /// the step came to rest in.
    private static func steps(_ lines: [String]) -> [String] {
        segments(lines).map { step in
            only(step.lines, ["T configure"]).sorted().joined(separator: "|") + " => "
                + (only(step.lines, ["T prefetch"]).last ?? "")
        }
    }

    private static func firstDifference(_ first: [String], _ second: [String]) -> String {
        for (index, (one, two)) in zip(first, second).enumerated() where one != two {
            return "at \(index): '\(one)' / '\(two)'"
        }
        return "lengths \(first.count) / \(second.count)"
    }

    /// The lines only in one or only in the other, counted.
    private static func difference(_ first: [String], _ second: [String]) -> String {
        var counts: [String: Int] = [:]
        first.forEach { counts[$0, default: 0] += 1 }
        second.forEach { counts[$0, default: 0] -= 1 }
        let onlyFirst = counts.filter { $0.value > 0 }.keys.sorted()
        let onlySecond = counts.filter { $0.value < 0 }.keys.sorted()
        return "only first \(onlyFirst.prefix(6)) only second \(onlySecond.prefix(6))"
    }
}
#endif
