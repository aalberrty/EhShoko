import EhCore
import EhFeatures
import EhModels
import Foundation
import UIKit

// What Settings › Translation says about the package's values: names, labels, units, the
// headings of what a figure was measured on, and the states of downloads. Model names and
// the phone's name are not translated (`README.md` section 10).

private typealias Strings = L10n.Localizable.Settings.Translation
private typealias Download = L10n.Localizable.Translation.Download

/// The kind of device the strings name ("iPhone", "iPad"), untranslated.
enum PageTranslationDevice {
    static let name = UIDevice.current.model
}

extension ModelRole {
    /// The row on the Translation screen and the title of its selection screen.
    var title: String {
        switch self {
        case .detector: Strings.detector
        case .reader: Strings.reader
        case .translator: Strings.translator
        case .repaint: Strings.repaint
        }
    }
}

extension PageTranslationChoice {
    /// The model's own name.
    var displayName: String {
        switch self {
        case .detector(let detector):
            switch detector {
            case .k2xl: "KoharuLayout 2XL"
            case .yolo26s: "Koharu YOLO26s"
            case .v4s: "ogkalu v4-s"
            case .rtmdet2: "RTMDet2"
            }
        case .reader(let reader):
            switch reader {
            case .cpt2: "manga-ocr-base CPT v2"
            case .narSmall: "manga-ocr-nar-small"
            }
        case .translator(let translator):
            switch translator {
            case .jmtFast1: "JMangaTranslator-Fast v1"
            case .galTransl4B: "GalTransl v4 4B"
            case .sakura1_5B: "Sakura 1.5B"
            case .hyMT2: "Hy-MT2 1.8B"
            case .qwen35_4B: "Qwen3.5 4B"
            }
        case .repaint(let repaint):
            switch repaint {
            case .off: L10n.Localizable.Enum.AutoPlayPolicy.Value.off
            case .lamaManga: "lama_large_512px"
            case .bigLama: "big-lama"
            }
        }
    }

    /// What it does, where the choices of a kind differ in what they do rather than in
    /// their figures: only the repaint choices.
    var summary: String? {
        guard case .repaint(let repaint) = self else { return nil }
        return switch repaint {
        case .off: Strings.Desc.Repaint.off
        case .lamaManga: Strings.Desc.Repaint.lamaManga
        case .bigLama: Strings.Desc.Repaint.bigLama
        }
    }
}

extension MeasuredFigure.Kind {
    var label: String {
        typealias Figure = Strings.Figure
        return switch self {
        case .balloonTextFound: Figure.foundBalloon
        case .notesFound: Figure.foundNotes
        case .linesReadExactly: Figure.readExact
        case .linesFullyRight: Figure.right
        case .linesWithSeriousError: Figure.serious
        case .timePerPage: Figure.timePage
        case .timePerBlock: Figure.timeBlock
        case .timePerTile: Figure.timeTile
        case .memory: Figure.memory
        case .graphicsMemory: Figure.memoryGpu
        case .firstLoad: Figure.firstLoad
        case .heat: Figure.heat
        case .pictureMatches: Figure.picture
        }
    }
}

extension MeasuredFigure.Value {
    /// The value as a selection card shows it. A time below one second is in whole
    /// milliseconds (0.0179 s is 18 ms), above it in seconds with up to two decimals as
    /// measured (1.65 s, 27.8 s); megabytes as the system writes them.
    var text: String {
        typealias Value = Strings.Value
        switch self {
        case .tally(let count, let total):
            return Value.tally(count, total)
        case .seconds(let seconds) where seconds < 1:
            // Through microseconds, so 0.0105 s rounds to 11 ms and not to 10.
            let microseconds = Int((seconds * 1_000_000).rounded())
            return Value.milliseconds(((microseconds + 500) / 1000).formatted())
        case .seconds(let seconds):
            return Value.seconds(seconds.formatted(.number.precision(.fractionLength(0...2))))
        case .megabytes(let megabytes):
            return Measurement(value: Double(megabytes), unit: UnitInformationStorage.megabytes)
                .formatted(.measurement(width: .abbreviated, usage: .asProvided))
        case .coolFor(let pages):
            return Value.heatCool(pages)
        case .hotFrom(let page):
            return Value.heatHot(page)
        case .notMeasured:
            return Value.notMeasured
        }
    }
}

extension MeasuredFigure.Basis {
    /// The heading over the figures measured on it, in sentence case; a card capitalises it.
    var heading: String {
        typealias Basis = Strings.Basis
        return switch self {
        case .pagesPhone: Basis.pages(PageTranslationMeasurements.testPageCount)
        case .pagesMac: Basis.pagesMac(PageTranslationMeasurements.testPageCount)
        case .phone: Basis.phone(PageTranslationMeasurements.phoneName)
        case .mac: Basis.mac
        }
    }
}

extension MeasuredFigure.Note {
    var text: String {
        switch self {
        case .largerFile: Strings.Note.largerFile
        }
    }
}

extension MeasuredFigure {
    /// The top card's line: what the current detector and reader read together.
    var pairText: String {
        guard case .tally(let count, let total) = value else { return Strings.Pair.notMeasured }
        return Strings.pair(count, total, PageTranslationMeasurements.testPageCount)
    }
}

extension Int64 {
    /// A download or file size as the system writes it.
    var byteText: String {
        formatted(.byteCount(style: .file))
    }
}

extension ModelTransferProgress {
    /// "412 MB of 1.18 GB".
    var text: String {
        Download.progress(completedBytes.byteText, totalBytes.byteText)
    }

    var downloadingText: String {
        Strings.Status.downloading(completedBytes.byteText, totalBytes.byteText)
    }

    /// "Paused · 412 MB of 1.18 GB".
    var pausedText: String {
        Strings.Status.paused(completedBytes.byteText, totalBytes.byteText)
    }
}

@MainActor
extension ModelStoreFailure {
    /// What went wrong, where a text says more than "The download stopped".
    var detail: String? {
        switch self {
        // When the disk fills in the middle of a download both numbers are 0.
        case .noSpace(let needed, let available) where needed > 0 || available > 0:
            Download.noSpace(needed.byteText, available.byteText)
        case .noSource: Download.noSource
        case .checksumMismatch: Download.checksum
        case .noSpace, .refused, .unreachable, .installFailed: nil
        }
    }
}

extension ModelSetState {
    /// The state line of the models of the current choices, as the reader's download sheet
    /// can show it.
    var statusText: String {
        typealias Status = Strings.Status
        return switch self {
        case .unavailable: Download.noSource
        case .missing: Status.none
        case .downloading(let progress), .waitingForConnection(let progress): progress.downloadingText
        case .paused(let progress): progress.pausedText
        case .preparing: Status.preparing
        case .ready: Status.ready
        case .failed: Download.failed
        }
    }

    /// A second line, where there is more to say.
    func detail(isConnected: Bool) -> String? {
        switch self {
        case .waitingForConnection: Download.offline
        case .missing where !isConnected: Download.offline
        case .preparing: Download.preparing
        case .failed(let failure): failure.detail
        default: nil
        }
    }

    var progress: ModelTransferProgress? {
        switch self {
        case .downloading(let progress), .waitingForConnection(let progress), .paused(let progress): progress
        default: nil
        }
    }

    /// The top card's state line: with no source it points at the private source section
    /// under it rather than at Settings, where it already is.
    var settingsStatusText: String {
        self == .unavailable ? Strings.Status.noSource : statusText
    }

    func settingsDetail(isConnected: Bool) -> String? {
        if case .failed(.noSource) = self { return Strings.Status.noSource }
        return detail(isConnected: isConnected)
    }
}

extension PageTranslationSettingsModel.TopAction {
    var title: String {
        switch self {
        case .download(let bytes): Download.start(bytes.byteText)
        case .pause: Download.pause
        case .resume: Download.resume
        case .retry: L10n.Localizable.ErrorView.Button.retry
        }
    }
}

extension PageTranslationChoiceCard {
    /// "Default · Installed", "Needs 2.5 GB", "Downloading · 412 MB of 1.1 GB".
    var statusText: String {
        var parts: [String] = []
        if isDefault { parts.append(Strings.default) }
        switch availability {
        case .noDownload: break
        case .installed: parts.append(Strings.installed)
        case .needs(let bytes): parts.append(Strings.needs(bytes.byteText))
        case .downloading(let progress): parts.append(progress.downloadingText)
        case .paused(let progress): parts.append(progress.pausedText)
        case .preparing: parts.append(Strings.Status.preparing)
        case .failed(let failure): parts.append(failure.detail ?? Download.failed)
        case .notOffered: parts.append(Strings.notPublic)
        }
        return parts.joined(separator: " · ")
    }

    var progress: ModelTransferProgress? {
        switch availability {
        case .downloading(let progress), .paused(let progress): progress
        default: nil
        }
    }
}
