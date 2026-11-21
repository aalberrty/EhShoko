#if DEBUG || HARNESS
import EhCore
import EhPageTranslation
import Foundation

/// What a run writes: `Documents/TranslationHarness/Results/<label>-<time>.json`. Times are
/// milliseconds unless a name ends in `S` (seconds since the run began); sizes are bytes.
nonisolated struct TranslationHarnessResult: Codable, Sendable {
    var harness = "translation"
    var format = 1
    var label: String
    var run: String
    var startedAt: Date
    var endedAt: Date?
    /// `done`, or why the run ended early.
    var stoppedBecause: String?
    var device: Device
    var arguments: [String]
    var setup: Setup?
    var store: Store?
    var memory = Memory()
    var thermal = Thermal()
    var loads: [Load] = []
    var pages: [Page] = []
    var cancels: [Cancel] = []
    var lines: Lines?
    var summary: TranslationHarnessSummary?
    var notes: [String] = []

    struct Device: Codable, Sendable {
        var model: String
        var system: String
        var isSimulator: Bool
        /// A debug build is 50 to 100 times slower in the drawing: its times are not budget figures.
        var isDebugBuild: Bool
        var isLowPowerModeEnabled: Bool
        var processorCount: Int
        var physicalMemory: UInt64
    }

    struct Setup: Codable, Sendable {
        var modelSetKey: String
        var detector: String
        var reader: String
        var translator: String
        /// A language model's file used instead of the store's install.
        var translatorFile: String?
        /// What pages are drawn with: `fill` when the repaint model is off or not installed.
        var repaint: String
        var detectorUnits: String
        var readerUnits: String
        var translatorUnits: String
        var repaintUnits: String
        var contextLength: Int?
        var contextLengthApplied: Bool
    }

    struct Store: Codable, Sendable {
        struct Artifact: Codable, Sendable {
            var id: String
            var state: String
            /// When it became installed, if it was not already when the run began.
            var installedAtS: Double?
            var wasInstalledAtStart: Bool
        }

        var readyAfterS: Double
        var artifacts: [Artifact]
    }

    struct Memory: Codable, Sendable {
        /// Before the model store was looked at: the app with no translation.
        var baseline: TranslationHarnessSampler.Sample?
        var afterStoreReady: TranslationHarnessSampler.Sample?
        /// Three seconds after the session was closed, when every model should be let go.
        var afterClose: TranslationHarnessSampler.Sample?
        /// The highest and lowest of the whole run, sampled every 50 ms.
        var run: TranslationHarnessSampler.Sample?
        var lifetimeFootprintPeak: UInt64?
        var ballast: Int = 0
    }

    struct Thermal: Codable, Sendable {
        var atStart: String?
        var atEnd: String?
        /// The first page whose end found the phone at each state.
        var firstPage: [String: Int] = [:]
    }

    struct Load: Codable, Sendable {
        /// `pipeline` (detector, reader and translator as the service loads them), `repaint`,
        /// or a single model of the `load` run.
        var what: String
        var atS: Double
        var ms: Double
        var parts: [String: Double] = [:]
        var units: String?
        var failed: String?
    }

    struct Page: Codable, Sendable {
        var index: Int
        var file: String
        var askedAtS: Double
        var endedAtS: Double
        var status: String
        var source: String?
        var variant: String?
        var totalMs: Double?
        var waitingForModelsMs: Double?
        var fetchingMs: Double?
        var decodingMs: Double?
        var text: TextTimes?
        var drawing: DrawingTimes?
        var writingMs: Double?
        var patches: Int?
        var patchFileBytes: Int?
        var patchFileSHA256: String?
        var repaintedBlocks: Int?
        var failedRepaints: Int?
        var imageWidth: Int?
        var imageHeight: Int?
        var calls: [String: TranslationHarnessCalls.Tally]
        var memory: TranslationHarnessSampler.Sample
        var thermal: String
        var recorded: TranslationHarnessCalls.Text?
        /// A language model's requests for this page (`translateRecording`).
        var languageModel: [TranslationHarnessLanguageModel.Page]?
    }

    struct TextTimes: Codable, Sendable {
        var preparationMs: Double
        var networkMs: Double
        var decodingMs: Double
        var masksMs: Double
        /// Decoding and masks: what the budget of 2 ms covers.
        var afterNetworkMs: Double
        var readingMs: Double
        var translatingMs: Double
        /// Stages 1 to 4: the budget's "finding, reading and translating".
        var totalMs: Double
        var tiles: Int
        var blocksFound: Int
        var blocksRead: Int
        var emptyReadings: Int
        var untranslatedLines: Int
    }

    struct DrawingTimes: Codable, Sendable {
        var analysisMs: Double
        var fillingMs: Double
        var repaintingMs: Double
        var fittingMs: Double
        var drawingMs: Double
        var totalMs: Double
        /// Everything but the repaint model: the budget's 0.4 s.
        var withoutRepaintModelMs: Double
    }

    struct Cancel: Codable, Sendable {
        var index: Int
        var file: String
        var cancelledAfterS: Double
        /// The page was done before it could be cancelled.
        var finishedFirst: Bool
        var callsUnderWay: [String]
        /// From the cancel to the return of the last model call under way.
        var msUntilIdle: Double
    }

    struct Lines: Codable, Sendable {
        struct Page: Codable, Sendable {
            var page: String
            var ms: Double
            var lines: [Line]
            var languageModel: TranslationHarnessLanguageModel.Page?
        }

        struct Line: Codable, Sendable {
            var ja: String
            var zh: String?
        }

        var file: String
        var loadMs: Double
        var pages: [Page]
    }
}

nonisolated extension TranslationHarnessResult.Page {
    init(
        index: Int, file: String, askedAtS: Double, endedAtS: Double, event: PageTranslationEvent,
        calls: [String: TranslationHarnessCalls.Tally], memory: TranslationHarnessSampler.Sample,
        thermal: String, recorded: TranslationHarnessCalls.Text?
    ) {
        self.index = index
        self.file = file
        self.askedAtS = askedAtS
        self.endedAtS = endedAtS
        self.calls = calls
        self.memory = memory
        self.thermal = thermal
        self.recorded = recorded
        switch event.status {
        case let .translated(overlay):
            status = "translated"
            variant = overlay.variant
        case .nothingToDraw: status = "nothingToDraw"
        case .skipped: status = "skipped"
        case let .failed(failure): status = "failed: \(failure)"
        case .loadingModels: status = "loadingModels"
        case .translating: status = "translating"
        }
        guard let report = event.report else { return }
        source = switch report.source {
        case .stored: "stored"
        case .redrawn: "redrawn"
        case .translated: "translated"
        }
        let ms = TranslationHarnessCalls.milliseconds
        totalMs = ms(report.total)
        waitingForModelsMs = ms(report.waitingForModels)
        fetchingMs = ms(report.fetching)
        decodingMs = ms(report.decoding)
        writingMs = ms(report.writing)
        patches = report.patches
        patchFileBytes = report.patchFileBytes
        repaintedBlocks = report.repaintedBlocks
        failedRepaints = report.failedRepaints
        imageWidth = report.imageWidth
        imageHeight = report.imageHeight
        if let text = report.text {
            self.text = TranslationHarnessResult.TextTimes(
                preparationMs: ms(text.detection.preparation), networkMs: ms(text.detection.network),
                decodingMs: ms(text.detection.decoding), masksMs: ms(text.detection.masks),
                afterNetworkMs: ms(text.detection.afterNetwork), readingMs: ms(text.reading),
                translatingMs: ms(text.translating), totalMs: ms(text.total), tiles: text.tiles,
                blocksFound: text.blocksFound, blocksRead: text.blocksRead, emptyReadings: text.emptyReadings,
                untranslatedLines: text.untranslatedLines
            )
        }
        if let drawing = report.drawing {
            self.drawing = TranslationHarnessResult.DrawingTimes(
                analysisMs: ms(drawing.analysis), fillingMs: ms(drawing.filling), repaintingMs: ms(drawing.repainting),
                fittingMs: ms(drawing.fitting), drawingMs: ms(drawing.drawing), totalMs: ms(drawing.total),
                withoutRepaintModelMs: ms(drawing.total - drawing.repainting)
            )
        }
    }
}

nonisolated extension TranslationHarnessResult.Device {
    static var current: Self {
        var system = utsname()
        uname(&system)
        let machine = withUnsafeBytes(of: system.machine) { bytes in
            String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
        }
        let info = ProcessInfo.processInfo
        #if targetEnvironment(simulator)
        let isSimulator = true
        #else
        let isSimulator = false
        #endif
        #if DEBUG
        let isDebugBuild = true
        #else
        let isDebugBuild = false
        #endif
        return Self(
            model: info.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? machine,
            system: info.operatingSystemVersionString, isSimulator: isSimulator, isDebugBuild: isDebugBuild,
            isLowPowerModeEnabled: info.isLowPowerModeEnabled, processorCount: info.activeProcessorCount,
            physicalMemory: info.physicalMemory
        )
    }
}

/// Writes a run's result, again after every page.
nonisolated enum TranslationHarnessOutput {
    static var folder: URL { TranslationHarnessOptions.folder.appending(path: "Results", directoryHint: .isDirectory) }

    static func url(label: String, startedAt: Date) -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let safe = label.map { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" ? $0 : "-" }
        return folder.appending(path: "\(String(safe))-\(formatter.string(from: startedAt)).json")
    }

    @concurrent
    static func write(_ result: TranslationHarnessResult, to url: URL) async throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        encoder.nonConformingFloatEncodingStrategy = .convertToString(
            positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan"
        )
        let data = try encoder.encode(result)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}
#endif
