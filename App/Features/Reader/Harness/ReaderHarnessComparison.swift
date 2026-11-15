#if DEBUG || HARNESS
import Foundation

/// Sets the records of two runs of the same script side by side: one without the closing
/// page's slot and one with it. Everything before the mark `last` (the reader has arrived on
/// the last page) must be the same; what comes after is listed, since with the slot the next
/// step reaches it.
///
/// "The same" cannot mean line for line. What the engine decides is compared in order: the
/// pages it needs and lets go, the current page, a retry, what it hands its prefetcher and
/// the page views it configures. What finishes when a delay or a download finishes is compared
/// as a set: images loaded with their decoded size, images failed, `aspectRatio` calls, the
/// `pageState` calls of page views. The `pageState` calls of the prefetcher's own passes are
/// only counted: a pass runs whenever a download ends, and two runs of the same engine
/// without the slot differ in their number.
struct ReaderHarnessComparison {
    enum Verdict: String {
        /// Every call in the same order.
        case identical = "every call identical up to the last page"
        /// All of the above, with the prefetcher's passes differing in number or order.
        case same = "same up to the last page (only the prefetcher's pageState passes differ)"
        /// The same step for step, but an animated scroll of the strip passed through other
        /// tile states on its way: which of them a frame lands on is a matter of timing.
        case sameAtRest = "same at every step's rest up to the last page (the animated strip passed other tile states)"
        /// The same once the last page's box and decoded size are set aside: the slot is
        /// beside it, so it is laid out and decoded for half the screen.
        case sameButLastPageSize = "same up to the last page but for the last page's size (the slot is beside it)"
        case different = "DIFFERENT"
    }

    private(set) var report: [String] = []
    private(set) var verdict = Verdict.different
    /// Whether the engine's trace matched only step for step, not line for line.
    private var matchesOnlyAtRest = false

    private static let pageEvents = ["E needs", "E release", "E page", "E retry"]
    private static let trace = ["T prefetch", "T configure"]
    /// The calls that exist because of the slot; set aside when two records are compared.
    private static let trailerCalls = ["D hasTrailer", "D makeTrailer", "E trailer"]

    init(off: [String], on: [String], lastPage: Int) {
        let (offHead, offTail) = Self.split(off)
        let (onHead, onTail) = Self.split(on)
        report.append("off: \(off.count) lines, \(offHead.count) before 'last'   "
            + "on: \(on.count) lines, \(onHead.count) before 'last'")
        report.append("Before the last page is reached (off / on):")
        let isSame = compareHeads(offHead, onHead, isReported: true)
        let isExact = Self.withoutTrailerCalls(offHead) == Self.withoutTrailerCalls(onHead)
        report.append("  \(isExact ? "SAME" : "DIFF")  every call in order, the slot's own calls set aside")
        countPasses(offHead, onHead)
        listTrailerCalls(onHead)
        compareTails(offTail, onTail)
        if isSame {
            verdict = isExact ? .identical : matchesOnlyAtRest ? .sameAtRest : .same
        } else {
            // Beside the last page the slot takes half the screen from it.
            let size = ["T configure \(lastPage) ", "E loaded \(lastPage) "]
            let offRest = offHead.filter { !Self.has($0, size) }
            let onRest = onHead.filter { !Self.has($0, size) }
            if compareHeads(offRest, onRest, isReported: false) {
                verdict = .sameButLastPageSize
                report.append("  page \(lastPage) off: " + Self.only(offHead, size).joined(separator: " | "))
                report.append("  page \(lastPage) on:  " + Self.only(onHead, size).joined(separator: " | "))
            }
        }
        report.append("RESULT: \(verdict.rawValue)")
    }

    // MARK: Before the mark

    private mutating func compareHeads(_ off: [String], _ on: [String], isReported: Bool) -> Bool {
        var isSame = true
        func check(_ name: String, _ first: [String], _ second: [String]) {
            let matches = first == second
            isSame = isSame && matches
            guard isReported else { return }
            let detail = matches ? "" : "  <-- " + Self.firstDifference(first, second)
            report.append("  \(matches ? "SAME" : "DIFF")  \(name): \(first.count) / \(second.count)\(detail)")
        }
        check("page events in order (needs, release, current page, retry)",
              Self.only(off, Self.pageEvents), Self.only(on, Self.pageEvents))
        check("images failed, sorted", Self.only(off, ["E failed"]).sorted(), Self.only(on, ["E failed"]).sorted())
        let offTrace = Self.only(off, Self.trace)
        let onTrace = Self.only(on, Self.trace)
        if offTrace == onTrace {
            check("engine trace in order (prefetcher inputs, page views configured)", offTrace, onTrace)
        } else {
            // An animated scroll of the strip passes through tile states between its start and
            // its end, and which of them a frame lands on is a matter of timing. What a step
            // configures, and the state it comes to rest in, is not.
            if isReported {
                report.append("  DIFF  engine trace in order: \(offTrace.count) / \(onTrace.count)  <-- "
                    + Self.firstDifference(offTrace, onTrace))
            }
            check("engine trace per step (page views configured, and the state it rests in)",
                  Self.restingStates(off), Self.restingStates(on))
            matchesOnlyAtRest = true
        }
        check("pageState asked by page views, sorted",
              Self.only(off, ["T content"]).sorted(), Self.only(on, ["T content"]).sorted())
        check("images loaded, as a set (page and decoded size)",
              Set(Self.only(off, ["E loaded"])).sorted(), Set(Self.only(on, ["E loaded"])).sorted())
        check("aspectRatio calls, sorted", Self.only(off, ["D aspect"]).sorted(), Self.only(on, ["D aspect"]).sorted())
        check("marks (the script took the same steps)", Self.only(off, ["M "]), Self.only(on, ["M "]))
        return isSame
    }

    private mutating func countPasses(_ off: [String], _ on: [String]) {
        func passes(_ lines: [String]) -> Int {
            Self.only(lines, ["D pageState"]).count - Self.only(lines, ["T content"]).count
        }
        report.append("  pageState asked by the prefetcher's passes (varies with download timing): "
            + "\(passes(off)) / \(passes(on))")
    }

    private mutating func listTrailerCalls(_ on: [String]) {
        let made = on.firstIndex(of: "D makeTrailer")
        let marks = made.map { Self.only(Array(on[..<$0]), ["M "]) } ?? []
        let visibility = Self.only(on, ["E trailer"])
        report.append("  before the last page, with the slot: closing page "
            + (made == nil ? "not asked for" : "asked for after mark '\(marks.last ?? "none")'")
            + ", visibility calls \(visibility.count)")
    }

    // MARK: From the mark on

    private mutating func compareTails(_ off: [String], _ on: [String]) {
        report.append("From the last page on (off / on):")
        for (offStep, onStep) in zip(Self.steps(off), Self.steps(on)) {
            let first = Self.counts(Self.withoutTrailerCalls(offStep.lines))
            let second = Self.counts(Self.withoutTrailerCalls(onStep.lines))
            let calls = Self.only(onStep.lines, Self.trailerCalls)
            var line = "  '\(offStep.mark)' / '\(onStep.mark)': "
            line += first == second ? "same page calls"
                : "only off \(Self.surplus(first, over: second)) only on \(Self.surplus(second, over: first))"
            if !calls.isEmpty {
                line += "; slot calls \(calls)"
            }
            report.append(line)
        }
    }

    // MARK: Lines

    /// The lines before the mark `last`, and the rest.
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

    private static func withoutTrailerCalls(_ lines: [String]) -> [String] {
        lines.filter { !has($0, trailerCalls) }
    }

    /// Lines grouped by the script step they belong to: a step ends with its `M` line.
    private static func steps(_ lines: [String]) -> [(mark: String, lines: [String])] {
        var groups: [(mark: String, lines: [String])] = []
        var current: [String] = []
        for line in lines {
            if line.hasPrefix("M ") {
                groups.append((String(line.dropFirst(2)), current))
                current = []
            } else {
                current.append(line)
            }
        }
        if !current.isEmpty {
            groups.append(("(after the last mark)", current))
        }
        return groups
    }

    /// Per step: the page views it configured, sorted, and the last thing the prefetcher was
    /// handed, which is the state the step came to rest in.
    private static func restingStates(_ lines: [String]) -> [String] {
        steps(lines).map { step in
            let configured = only(step.lines, ["T configure"]).sorted().joined(separator: ", ")
            return "\(step.mark): [\(configured)] \(only(step.lines, ["T prefetch"]).last ?? "")"
        }
    }

    private static func counts(_ lines: [String]) -> [String: Int] {
        lines.reduce(into: [:]) { $0[$1, default: 0] += 1 }
    }

    /// What `first` has more of than `second`, with how many more.
    private static func surplus(_ first: [String: Int], over second: [String: Int]) -> String {
        let extra = first.compactMap { line, count -> String? in
            let more = count - (second[line] ?? 0)
            return more > 0 ? (more > 1 ? "\(more)× \(line)" : line) : nil
        }
        return "[" + extra.sorted().joined(separator: "; ") + "]"
    }

    private static func firstDifference(_ first: [String], _ second: [String]) -> String {
        for (index, pair) in zip(first, second).enumerated() where pair.0 != pair.1 {
            return "at \(index): off '\(pair.0)' / on '\(pair.1)'"
        }
        return "lengths \(first.count) / \(second.count)"
    }
}
#endif
