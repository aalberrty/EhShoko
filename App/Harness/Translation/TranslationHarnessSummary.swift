#if DEBUG || HARNESS
import Foundation

/// A run's figures against the budgets of the translation README's section 12. Each check
/// says whether it is a budget figure at all: a debug build or a simulator never is.
nonisolated struct TranslationHarnessSummary: Codable, Sendable {
    struct Statistic: Codable, Sendable {
        var count: Int
        var meanMs: Double
        var medianMs: Double
        var maxMs: Double
    }

    struct Check: Codable, Sendable {
        var what: String
        var budget: String
        var measured: String
        var isWithin: Bool
    }

    var pages = 0
    var statuses: [String: Int] = [:]
    var sources: [String: Int] = [:]
    /// Stages 1 to 4 of the pages translated now.
    var neural: Statistic?
    var detectionAfterNetwork: Statistic?
    var drawing: Statistic?
    var drawingWithoutRepaintModel: Statistic?
    var writing: Statistic?
    var pageTotal: Statistic?
    /// Each repaint model call: one tile.
    var repaintTiles: Int = 0
    var repaintTileMeanMs: Double?
    var repaintTileMaxMs: Double?
    var firstPageWaitingForModelsMs: Double?
    var peakAboveBaselineMB: Double?
    var gpuPeakMB: Double?
    var afterCloseAboveBaselineMB: Double?
    /// Files drawn more than once in the run, and how many of them came out different.
    var filesDrawnAgain = 0
    var filesDrawnDifferently = 0
    var cancelMsUntilIdleMax: Double?
    var isBudgetFigure: Bool
    var checks: [Check] = []

    init(_ result: TranslationHarnessResult) {
        isBudgetFigure = !result.device.isDebugBuild && !result.device.isSimulator
        pages = result.pages.count
        for page in result.pages {
            statuses[page.status.components(separatedBy: ":")[0], default: 0] += 1
            if let source = page.source { sources[source, default: 0] += 1 }
        }
        let computed = result.pages.filter { $0.source == "translated" }
        neural = Self.statistic(computed.compactMap(\.text?.totalMs))
        detectionAfterNetwork = Self.statistic(computed.compactMap(\.text?.afterNetworkMs))
        let drawn = result.pages.filter { $0.drawing != nil }
        drawing = Self.statistic(drawn.compactMap(\.drawing?.totalMs))
        drawingWithoutRepaintModel = Self.statistic(drawn.compactMap(\.drawing?.withoutRepaintModelMs))
        writing = Self.statistic(drawn.compactMap(\.writingMs))
        pageTotal = Self.statistic(result.pages.compactMap(\.totalMs))
        let tiles = result.pages.compactMap { $0.calls["repaint"] }
        repaintTiles = tiles.reduce(0) { $0 + $1.calls }
        if repaintTiles > 0 {
            repaintTileMeanMs = tiles.reduce(0) { $0 + $1.totalMs } / Double(repaintTiles)
            repaintTileMaxMs = tiles.map(\.longestMs).max()
        }
        firstPageWaitingForModelsMs = computed.first?.waitingForModelsMs
        let megabyte = 1_048_576.0
        // Only a run through the service is the reader's memory; the load run holds one model at a time.
        if result.run != "load", result.run != "lines", let baseline = result.memory.baseline {
            if let run = result.memory.run {
                peakAboveBaselineMB = (Double(run.footprintPeak) - Double(baseline.footprint)) / megabyte
                gpuPeakMB = Double(run.gpuPeak) / megabyte
            }
            if let afterClose = result.memory.afterClose {
                afterCloseAboveBaselineMB = (Double(afterClose.footprint) - Double(baseline.footprint)) / megabyte
            }
        }
        var hashes: [String: Set<String>] = [:]
        for page in result.pages {
            guard let hash = page.patchFileSHA256 else { continue }
            hashes[page.file, default: []].insert(hash)
        }
        let drawnAgain = Dictionary(grouping: result.pages.filter { $0.patchFileSHA256 != nil }, by: \.file)
            .filter { $0.value.count > 1 }
        filesDrawnAgain = drawnAgain.count
        filesDrawnDifferently = drawnAgain.keys.filter { (hashes[$0]?.count ?? 0) > 1 }.count
        cancelMsUntilIdleMax = result.cancels.map(\.msUntilIdle).max()
        checks = Self.checks(self, result: result)
    }

    private static func checks(_ summary: Self, result: TranslationHarnessResult) -> [Check] {
        var checks: [Check] = []
        func seconds(_ ms: Double) -> String { String(format: "%.2f s", ms / 1_000) }
        if let neural = summary.neural {
            checks.append(Check(
                what: "Finding, reading and translating a page, mean", budget: "1.0 s",
                measured: seconds(neural.meanMs), isWithin: neural.meanMs <= 1_000
            ))
            checks.append(Check(
                what: "Finding, reading and translating the densest page", budget: "2.0 s",
                measured: seconds(neural.maxMs), isWithin: neural.maxMs <= 2_000
            ))
        }
        if let drawing = summary.drawingWithoutRepaintModel {
            checks.append(Check(
                what: "Repainting and drawing a page without the repaint model, worst", budget: "0.4 s",
                measured: seconds(drawing.maxMs), isWithin: drawing.maxMs <= 400
            ))
        }
        if let tile = summary.repaintTileMaxMs {
            checks.append(Check(
                what: "Each repaint model tile, worst", budget: "0.6 s", measured: seconds(tile), isWithin: tile <= 600
            ))
        }
        if let waiting = summary.firstPageWaitingForModelsMs {
            checks.append(Check(
                what: "Getting ready: the first page's wait for the models (30 s after a cold start, 3 s otherwise)",
                budget: "30 s", measured: seconds(waiting), isWithin: waiting <= 30_000
            ))
        }
        if let peak = summary.peakAboveBaselineMB {
            let withRepaint = result.loads.contains { $0.what == "repaint" && $0.failed == nil }
            let budget = withRepaint ? 420.0 : 150.0
            checks.append(Check(
                what: withRepaint ? "Memory with the repaint model loaded, above the baseline" : "Memory, above the baseline",
                budget: "\(Int(budget)) MB", measured: String(format: "%.0f MB", peak), isWithin: peak <= budget
            ))
        }
        if let after = summary.afterCloseAboveBaselineMB {
            checks.append(Check(
                what: "After the session closed, above the baseline", budget: "5 MB",
                measured: String(format: "%.1f MB", after), isWithin: after <= 5
            ))
        }
        let intervalArgument = result.arguments.firstIndex(of: "-TranslationHarnessInterval")
        let interval = intervalArgument.flatMap { result.arguments.dropFirst($0 + 1).first }.flatMap(Double.init) ?? 0
        if interval >= 10, result.pages.count >= 40 {
            let serious = result.thermal.firstPage["serious"] ?? result.thermal.firstPage["critical"]
            checks.append(Check(
                what: "Heat: the pages at one every ten seconds stay below serious", budget: "below serious",
                measured: serious.map { "serious at page \($0 + 1)" } ?? "never serious",
                isWithin: serious == nil
            ))
        }
        return checks
    }

    private static func statistic(_ values: [Double]) -> Statistic? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        let median = sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
        return Statistic(
            count: values.count, meanMs: values.reduce(0, +) / Double(values.count), medianMs: median,
            maxMs: sorted[sorted.count - 1]
        )
    }
}
#endif
