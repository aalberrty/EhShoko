#if DEBUG || HARNESS
import CoreGraphics
import EhModels
import EhPageTranslation
import Foundation
import Synchronization

/// Every model call of a run, counted where it is made: the harness wraps the detector,
/// the reader, the translator and the repaint model the service loads. The service's own
/// report has the stage times; these add what it does not keep: each repaint tile, the
/// longest single call, and which call was under way when a page was cancelled.
///
/// With the `single` window every call between two pages' ends is the later page's. With
/// the `reader` window pages overlap, and the tallies are only a sum.
nonisolated final class TranslationHarnessCalls: Sendable {
    enum Stage: String, Sendable, Codable, CaseIterable {
        case detect, read, translate, repaint
    }

    struct Tally: Sendable, Codable, Equatable {
        var calls = 0
        var totalMs: Double = 0
        var longestMs: Double = 0
    }

    /// What a page's calls were, when the text is recorded.
    struct Text: Sendable, Codable, Equatable {
        struct Block: Sendable, Codable, Equatable {
            /// x, y, width and height in the working bitmap's pixels.
            var box: [Double]
            var kind: String
            var score: Double
            var isVertical: Bool
            var inBalloon: Bool
        }

        struct Translation: Sendable, Codable, Equatable {
            var lines: [String]
            var results: [String?]
        }

        var detections: [[Block]] = []
        var readings: [String] = []
        var translations: [Translation] = []
    }

    /// The call under way when `cancelled` was noted, and when the last call returned.
    struct Cancel: Sendable, Codable, Equatable {
        var stagesUnderWay: [Stage]
        var msUntilIdle: Double
    }

    private struct State {
        var tallies: [Stage: Tally] = [:]
        var text = Text()
        var languageModel: [TranslationHarnessLanguageModel.Page] = []
        var underWay: [Int: Stage] = [:]
        var nextCall = 0
        var lastReturn: ContinuousClock.Instant?
    }

    let recordsText: Bool
    private let clock = ContinuousClock()
    private let state = Mutex(State())

    init(recordsText: Bool) {
        self.recordsText = recordsText
    }

    /// Times `body` as one call of `stage`.
    func measure<T: Sendable>(_ stage: Stage, _ body: () async throws -> T) async rethrows -> T {
        let call = state.withLock { state in
            state.nextCall += 1
            state.underWay[state.nextCall] = stage
            return state.nextCall
        }
        let start = clock.now
        defer {
            let end = clock.now
            let ms = Self.milliseconds(end - start)
            state.withLock { state in
                state.underWay[call] = nil
                state.lastReturn = end
                var tally = state.tallies[stage] ?? Tally()
                tally.calls += 1
                tally.totalMs += ms
                tally.longestMs = max(tally.longestMs, ms)
                state.tallies[stage] = tally
            }
        }
        return try await body()
    }

    func record(_ update: (inout Text) -> Void) {
        guard recordsText else { return }
        state.withLock { update(&$0.text) }
    }

    func record(_ page: TranslationHarnessLanguageModel.Page) {
        state.withLock { $0.languageModel.append(page) }
    }

    /// What was counted since the last call, which starts again from nothing.
    func take() -> (
        tallies: [String: Tally], text: Text?, languageModel: [TranslationHarnessLanguageModel.Page]
    ) {
        state.withLock { state in
            let tallies = Dictionary(uniqueKeysWithValues: state.tallies.map { ($0.key.rawValue, $0.value) })
            let text = recordsText ? state.text : nil
            let languageModel = state.languageModel
            state.tallies = [:]
            state.text = Text()
            state.languageModel = []
            return (tallies, text, languageModel)
        }
    }

    var stagesUnderWay: [Stage] {
        state.withLock { Array(Set($0.underWay.values)).sorted { $0.rawValue < $1.rawValue } }
    }

    var isIdle: Bool { state.withLock { $0.underWay.isEmpty } }

    /// Waits until no call is under way, and says how long after `since` the last one returned.
    func idle(since: ContinuousClock.Instant, timeout: Duration = .seconds(60)) async -> Double {
        let deadline = since + timeout
        while !isIdle, clock.now < deadline {
            try? await Task.sleep(for: .milliseconds(2))
        }
        guard let lastReturn = state.withLock({ $0.lastReturn }), lastReturn > since else { return 0 }
        return Self.milliseconds(lastReturn - since)
    }

    static func milliseconds(_ duration: Duration) -> Double {
        let parts = duration.components
        return Double(parts.seconds) * 1_000 + Double(parts.attoseconds) / 1e15
    }
}

// MARK: - The wrapped models

nonisolated struct TimedDetector: TextDetector {
    let inner: any TextDetector
    let calls: TranslationHarnessCalls

    var choice: TextDetectorChoice { inner.choice }

    @concurrent
    func detect(_ page: PageBitmap, in region: PixelRect) async throws -> DetectedText {
        let found = try await calls.measure(.detect) { try await inner.detect(page, in: region) }
        calls.record { $0.detections.append(found.blocks.map(TranslationHarnessCalls.Text.Block.init)) }
        return found
    }
}

nonisolated struct TimedReader: TextReader {
    let inner: any TextReader
    let calls: TranslationHarnessCalls

    var choice: TextReaderChoice { inner.choice }

    @concurrent
    func read(_ crop: CGImage) async throws -> String {
        let text = try await calls.measure(.read) { try await inner.read(crop) }
        calls.record { $0.readings.append(text) }
        return text
    }
}

nonisolated struct TimedTranslator: PageTranslator {
    let inner: any PageTranslator
    let calls: TranslationHarnessCalls

    @concurrent
    func translate(_ lines: [String]) async throws -> [String?] {
        let results: [String?]
        if let model = inner as? LanguageModelTranslator {
            // The same call the translator makes for `translate`, with its requests kept.
            let page = try await calls.measure(.translate) { try await model.translateRecording(lines) }
            calls.record(TranslationHarnessLanguageModel.Page(page))
            results = page.lines
        } else {
            results = try await calls.measure(.translate) { try await inner.translate(lines) }
        }
        calls.record { $0.translations.append(.init(lines: lines, results: results)) }
        return results
    }
}

nonisolated struct TimedInpainter: Inpainter {
    let inner: any Inpainter
    let calls: TranslationHarnessCalls

    @concurrent
    func repaint(tile: [UInt8], mask: [UInt8]) async throws -> [UInt8] {
        try await calls.measure(.repaint) { try await inner.repaint(tile: tile, mask: mask) }
    }
}

nonisolated extension TranslationHarnessCalls.Text.Block {
    init(_ block: TextBlock) {
        box = [block.box.minX, block.box.minY, block.box.width, block.box.height].map { Double($0) }
        kind = block.kind.rawValue
        score = Double(block.score)
        isVertical = block.isVertical
        inBalloon = block.balloon != nil
    }
}

nonisolated extension PagePipeline {
    /// The same pipeline with every model call counted.
    func timed(by calls: TranslationHarnessCalls) -> PagePipeline {
        var pipeline = PagePipeline(
            detector: TimedDetector(inner: detector, calls: calls),
            reader: TimedReader(inner: reader, calls: calls),
            translator: TimedTranslator(inner: translator, calls: calls),
            rules: rules
        )
        pipeline.loadTimings = loadTimings
        return pipeline
    }
}
#endif
