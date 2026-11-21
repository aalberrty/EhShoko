import EhCore
import Foundation

private typealias Download = L10n.Localizable.Translation.Download

/// What the download sheet shows for where the required models stand (`MT6`'s table of
/// `ModelSetState`): the progress, the lines under it and its two buttons. A value made
/// from the store's state on each change, so the sheet's view only lays it out.
struct ReaderTranslationDownloadContent: Equatable {
    /// A button of the sheet.
    enum Action: Equatable {
        /// Downloads what is left (`bytes`) of the required models.
        case download(bytes: Int64)
        case pause
        case resume
        /// Downloads again after a failure.
        case retry
        /// Pushes Settings › Translation inside the sheet, where the source is entered.
        case openSettings
        /// Closes the sheet; the reader stays as it was.
        case keepReading

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

    /// The bar's fraction; `nil` for no bar.
    var fraction: Double?
    /// The line under the bar, or where the bar would be: "412 MB of 1.18 GB",
    /// "Paused · 412 MB of 1.18 GB", "The download stopped".
    var statusLine: String?
    /// What more there is to say: no connection, preparing, no space, no source, a checksum.
    var detail: String?
    /// The leading button, a secondary one; `nil` when the sheet has one button.
    var secondary: Action?
    /// The trailing button, the prominent one.
    var primary: Action
    /// Whether the time left is worth estimating: only while bytes arrive.
    var isTransferring: Bool

    init(state: ModelSetState, isConnected: Bool) {
        fraction = state.progress?.fraction
        statusLine = nil
        detail = state.detail(isConnected: isConnected)
        secondary = .keepReading
        isTransferring = false
        switch state {
        case .missing(let bytes):
            primary = .download(bytes: bytes)
        case .downloading(let progress):
            statusLine = progress.text
            isTransferring = true
            secondary = .pause
            primary = .keepReading
        case .waitingForConnection(let progress):
            statusLine = progress.text
            secondary = .pause
            primary = .keepReading
        case .paused(let progress):
            statusLine = progress.pausedText
            primary = .resume
        case .preparing:
            // Everything has arrived; the models are checked, compiled and loaded once.
            fraction = 1
            secondary = nil
            primary = .keepReading
        case .ready:
            statusLine = state.statusText
            secondary = nil
            primary = .keepReading
        case .unavailable, .failed(.noSource):
            detail = Download.noSource
            primary = .openSettings
        case .failed:
            statusLine = Download.failed
            primary = .retry
        }
    }
}

/// The time left of a download, from how its bytes moved while the sheet watched: the store
/// gives bytes, not a rate (`MT6`'s report, section 8). The average since the bytes started
/// moving, so the ranges the system delivers in bursts do not make it jump; it says nothing
/// for the first few seconds, and starts again after a pause or when the bytes go back.
struct ReaderTranslationDownloadPace {
    /// How long the bytes must be watched before a time is shown.
    static let settling: Duration = .seconds(5)

    private var start: (bytes: Int64, time: ContinuousClock.Instant)?
    private var latest: (bytes: Int64, time: ContinuousClock.Instant)?

    /// Notes the progress at `time`; `nil` while nothing is transferring.
    mutating func note(_ progress: ModelTransferProgress?, at time: ContinuousClock.Instant) {
        guard let progress else {
            start = nil
            latest = nil
            return
        }
        if let start, progress.completedBytes >= start.bytes {
            latest = (progress.completedBytes, time)
        } else {
            start = (progress.completedBytes, time)
            latest = nil
        }
    }

    /// "about 2 min left", once the bytes have been watched long enough to tell.
    func remainingText(of progress: ModelTransferProgress) -> String? {
        guard let start, let latest else { return nil }
        let elapsed = latest.time - start.time
        let moved = latest.bytes - start.bytes
        guard elapsed >= Self.settling, moved > 0 else { return nil }
        let seconds: Double = elapsed / Duration.seconds(1)
        let rate = Double(moved) / seconds
        let left = Double(max(0, progress.totalBytes - progress.completedBytes)) / rate
        // Whole minutes, at least one: seconds would change at every report.
        let minutes = max(1, (left / 60).rounded(.up))
        let text = Duration.seconds(minutes * 60).formatted(
            .units(allowed: [.hours, .minutes], width: .abbreviated, maximumUnitCount: 2)
        )
        return Download.remaining(text)
    }
}
