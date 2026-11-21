#if DEBUG || HARNESS
import CoreML
import EhModels
import Foundation

/// How a translation harness run is set up (`-Harness translation`), read from the launch
/// arguments. Paths are relative to the app's container (its home folder), where
/// `devicectl device copy to --domain-type appDataContainer` puts files.
///
/// | Argument | Default | Meaning |
/// |---|---|---|
/// | `-TranslationHarnessRun <kind>` | `pages` | `pages`: the real service over the folder. `cancel`: each page is cancelled `-TranslationHarnessCancelAfter` seconds after it was asked for, and the time until the model call under way returns is kept. `load`: every model and each of the translator's input lengths loaded once, alone, with Core ML. `lines`: the translator alone over a file of lines. `clean`: deletes the harness's folder and cache (copy the results off first). |
/// | `-TranslationHarnessLabel <text>` | the run | Names the result file and is shown on screen. |
/// | `-TranslationHarnessPagesFolder <path>` | `Documents/TranslationHarness/Pages` | The pages, taken in the order of their file names. |
/// | `-TranslationHarnessPages <n>` | the folder's count | How many pages are asked for. More than the folder holds goes round it again; every page asked for has a number of its own, so none is found in the cache. |
/// | `-TranslationHarnessInterval <s>` | 0 | Seconds from one page being asked for to the next; 0 is back to back (the next once the page is done). |
/// | `-TranslationHarnessWindow <single\|reader>` | `single` | `single`: only the page on screen is asked for, so every call is that page's. `reader`: the window a reader sends (the page, three ahead, the one before), trimmed by the service's policy. |
/// | `-TranslationHarnessDetector <choice>` | `k2xl` | `TextDetectorChoice`'s raw value. |
/// | `-TranslationHarnessReader <choice>` | `cpt2` | `TextReaderChoice`'s raw value. |
/// | `-TranslationHarnessTranslator <choice>` | `jmtFast1` | `TranslatorChoice`'s raw value. |
/// | `-TranslationHarnessModelFile <path>` | none | A language model's file in the container, used instead of the store's install of the translator. |
/// | `-TranslationHarnessContext <n>` | the profile's | A language model's context length. |
/// | `-TranslationHarnessRepaint <choice>` | `lamaManga` | `RepaintChoice`'s raw value; `off` draws without the repaint model. |
/// | `-TranslationHarness{Detector,Reader,Translator,Repaint}Units <units>` | the catalog's | `cpuOnly`, `cpuAndGPU`, `cpuAndNeuralEngine` or `all`. |
/// | `-TranslationHarnessBallast <MB>` | 0 | Memory held, written to, for the whole run: a full image cache is 512. |
/// | `-TranslationHarnessStartWhenWarm YES` | NO | Start although the thermal state is above nominal. Otherwise the run refuses and says so. |
/// | `-TranslationHarnessStopAt <fair\|serious\|critical>` | `serious` | Stop when the thermal state reaches this. Serious is where the system starts to throttle, so a run that goes past it measures a phone in distress. |
/// | `-TranslationHarnessStopOnFailure YES` | NO | Stop at the first page that fails. |
/// | `-TranslationHarnessMaxMinutes <m>` | 14 | Stop after this long, whatever is left. |
/// | `-TranslationHarnessRecordText YES` | NO | Keep each page's blocks, readings and translations in the result. |
/// | `-TranslationHarnessKeepCache YES` | NO | Keep the harness's cache from the launch before, so its pages are found stored. |
/// | `-TranslationHarnessDropPatches YES` | NO | With `KeepCache`: delete the patch files and keep the text, so stored pages are drawn again. |
/// | `-TranslationHarnessCancelAfter <s>` | 0.3 | For `cancel`. |
/// | `-TranslationHarnessLines <path>` | `Documents/TranslationHarness/lines.json` | For `lines`: `{"pages": [{"page": …, "lines": [{"ja": …}]}]}`, the shape of the translator's reference files. |
/// | `-TranslationHarnessExitWhenDone YES` | NO | Quit after writing the result. Otherwise the screen says it is done and the phone locks itself as usual. |
///
/// Results are written to `Documents/TranslationHarness/Results/<label>-<time>.json`, again
/// after every page, so a run that is cut short keeps what it measured.
nonisolated struct TranslationHarnessOptions: Sendable, Equatable {
    enum Run: String, Sendable, Codable {
        case pages, cancel, load, lines, clean
    }

    enum Window: String, Sendable, Codable {
        case single, reader
    }

    var run = Run.pages
    var label = ""
    var pagesFolder = "Documents/TranslationHarness/Pages"
    /// 0: one of each file in the folder.
    var pageCount = 0
    var interval: Double = 0
    var window = Window.single
    var modelSet = PageTranslationModelSet.default
    var modelFile: String?
    var contextLength: Int?
    var repaint = RepaintChoice.lamaManga
    var detectorUnits: MLComputeUnits?
    var readerUnits: MLComputeUnits?
    var translatorUnits: MLComputeUnits?
    var repaintUnits: MLComputeUnits?
    var ballastMB = 0
    var startsWhenWarm = false
    var stopAt = ProcessInfo.ThermalState.serious
    var stopsOnFailure = false
    var maxMinutes: Double = 14
    var recordsText = false
    var keepsCache = false
    var dropsPatches = false
    var cancelAfter: Double = 0.3
    var linesFile = "Documents/TranslationHarness/lines.json"
    var exitsWhenDone = false

    static var atLaunch: TranslationHarnessOptions { TranslationHarnessOptions(defaults: .standard) }

    init() {}

    init(defaults: UserDefaults) {
        func string(_ key: String) -> String? {
            defaults.string(forKey: "TranslationHarness" + key).flatMap { $0.isEmpty ? nil : $0 }
        }
        func number(_ key: String) -> Double? { string(key).flatMap(Double.init) }
        func flag(_ key: String) -> Bool { defaults.bool(forKey: "TranslationHarness" + key) }

        run = string("Run").flatMap(Run.init(rawValue:)) ?? .pages
        label = string("Label") ?? run.rawValue
        pagesFolder = string("PagesFolder") ?? pagesFolder
        pageCount = max(0, Int(number("Pages") ?? 0))
        interval = max(0, number("Interval") ?? 0)
        window = string("Window").flatMap(Window.init(rawValue:)) ?? .single
        modelSet = PageTranslationModelSet(
            detector: string("Detector").flatMap(TextDetectorChoice.init(rawValue:)) ?? .default,
            reader: string("Reader").flatMap(TextReaderChoice.init(rawValue:)) ?? .default,
            translator: string("Translator").flatMap(TranslatorChoice.init(rawValue:)) ?? .default
        )
        modelFile = string("ModelFile")
        contextLength = number("Context").map { Int($0) }
        repaint = string("Repaint").flatMap(RepaintChoice.init(rawValue:)) ?? .lamaManga
        detectorUnits = string("DetectorUnits").flatMap(Self.units)
        readerUnits = string("ReaderUnits").flatMap(Self.units)
        translatorUnits = string("TranslatorUnits").flatMap(Self.units)
        repaintUnits = string("RepaintUnits").flatMap(Self.units)
        ballastMB = min(max(0, Int(number("Ballast") ?? 0)), 4_096)
        startsWhenWarm = flag("StartWhenWarm")
        stopAt = string("StopAt").flatMap(Self.thermalState) ?? .serious
        stopsOnFailure = flag("StopOnFailure")
        maxMinutes = max(0.5, number("MaxMinutes") ?? 14)
        recordsText = flag("RecordText")
        keepsCache = flag("KeepCache")
        dropsPatches = flag("DropPatches")
        cancelAfter = max(0, number("CancelAfter") ?? 0.3)
        linesFile = string("Lines") ?? linesFile
        exitsWhenDone = flag("ExitWhenDone")
    }

    /// A path of the container as a file URL; an absolute path is taken as it is.
    static func containerURL(_ path: String) -> URL {
        if path.hasPrefix("/") { return URL(filePath: path) }
        return URL.homeDirectory.appending(path: path)
    }

    static let folder = containerURL("Documents/TranslationHarness")

    static func units(_ name: String) -> MLComputeUnits? {
        switch name {
        case "cpuOnly": .cpuOnly
        case "cpuAndGPU": .cpuAndGPU
        case "cpuAndNeuralEngine": .cpuAndNeuralEngine
        case "all": .all
        default: nil
        }
    }

    static func thermalState(_ name: String) -> ProcessInfo.ThermalState? {
        switch name {
        case "nominal": .nominal
        case "fair": .fair
        case "serious": .serious
        case "critical": .critical
        default: nil
        }
    }
}

nonisolated extension MLComputeUnits {
    var harnessName: String {
        switch self {
        case .cpuOnly: "cpuOnly"
        case .cpuAndGPU: "cpuAndGPU"
        case .cpuAndNeuralEngine: "cpuAndNeuralEngine"
        case .all: "all"
        @unknown default: "unknown"
        }
    }
}

nonisolated extension ProcessInfo.ThermalState {
    var harnessName: String {
        switch self {
        case .nominal: "nominal"
        case .fair: "fair"
        case .serious: "serious"
        case .critical: "critical"
        @unknown default: "unknown"
        }
    }
}
#endif
