import EhCore
import EhFeatures
import Foundation

private typealias Download = L10n.Localizable.Translation.Download

// The download sheet's texts. What it shows for each state is decided by
// `ReaderTranslationDownloadContent` in `EhFeatures`.

extension ReaderTranslationDownloadContent.Action {
    var title: String {
        switch self {
        case .download(let bytes): Download.start(bytes.byteText)
        case .pause: Download.pause
        case .resume: Download.resume
        case .retry: L10n.Localizable.ErrorView.Button.retry
        case .openSettings: Download.openSettings
        case .keepReading: Download.keepReading
        }
    }
}

extension ReaderTranslationDownloadContent.Line {
    var text: String {
        switch self {
        case .progress(let progress): progress.text
        case .paused(let progress): progress.pausedText
        case .stopped: Download.failed
        case .ready: ModelSetState.ready.statusText
        }
    }
}

extension ReaderTranslationDownloadContent.Detail {
    var text: String {
        switch self {
        case .offline: Download.offline
        case .preparing: Download.preparing
        case .noSource: Download.noSource
        case .noSpace(let needed, let available): Download.noSpace(needed.byteText, available.byteText)
        case .checksumMismatch: Download.checksum
        }
    }
}

extension Duration {
    /// "about 2 min left".
    var downloadRemainingText: String {
        Download.remaining(formatted(.units(allowed: [.hours, .minutes], width: .abbreviated, maximumUnitCount: 2)))
    }
}
