import EhCore

/// What the reader's download sheet shows for where the required models stand (`MT6`'s table
/// of `ModelSetState`): the bar, the line under it, what more there is to say and the two
/// buttons. The app turns each case into its text and lays it out.
nonisolated public struct ReaderTranslationDownloadContent: Hashable, Sendable {
    /// A button of the sheet.
    public enum Action: Hashable, Sendable {
        /// Downloads what is left (`bytes`) of the required models.
        case download(bytes: Int64)
        case pause
        case resume
        /// Downloads again after a failure.
        case retry
        /// Pushes Settings › Translation inside the sheet: the source is entered there, and
        /// its Storage section frees space.
        case openSettings
        /// Closes the sheet; the reader stays as it was.
        case keepReading
    }

    /// The line under the bar, or where the bar would be.
    public enum Line: Hashable, Sendable {
        /// "412 MB of 1.18 GB".
        case progress(ModelTransferProgress)
        /// "Paused · 412 MB of 1.18 GB".
        case paused(ModelTransferProgress)
        /// "The download stopped".
        case stopped
        /// "Ready · works offline".
        case ready
    }

    /// The line under the progress, where there is more to say.
    public enum Detail: Hashable, Sendable {
        /// No network: a download waits for one, or cannot start.
        case offline
        /// Everything has arrived; the models are checked, compiled and loaded once.
        case preparing
        /// No source offers a model: one is entered in Settings first.
        case noSource
        case noSpace(needed: Int64, available: Int64)
        case checksumMismatch
    }

    /// The bar's fraction; `nil` for no bar.
    public var fraction: Double?
    public var line: Line?
    public var detail: Detail?
    /// The leading button, a secondary one; `nil` when the sheet has one button.
    public var secondary: Action?
    /// The trailing button, the prominent one.
    public var primary: Action
    /// Whether bytes are arriving, so the time left is worth estimating.
    public var isTransferring: Bool

    public init(state: ModelSetState, isConnected: Bool) {
        fraction = nil
        line = nil
        detail = nil
        secondary = .keepReading
        isTransferring = false
        switch state {
        case .missing(let bytes):
            detail = isConnected ? nil : .offline
            primary = .download(bytes: bytes)
        case .downloading(let progress):
            fraction = progress.fraction
            line = .progress(progress)
            isTransferring = true
            secondary = .pause
            primary = .keepReading
        case .waitingForConnection(let progress):
            fraction = progress.fraction
            line = .progress(progress)
            detail = .offline
            secondary = .pause
            primary = .keepReading
        case .paused(let progress):
            fraction = progress.fraction
            line = .paused(progress)
            primary = .resume
        case .preparing:
            fraction = 1
            detail = .preparing
            secondary = nil
            primary = .keepReading
        case .ready:
            line = .ready
            secondary = nil
            primary = .keepReading
        case .unavailable, .failed(.noSource):
            detail = .noSource
            primary = .openSettings
        case .failed(.noSpace(let needed, let available)):
            line = .stopped
            // When the disk fills in the middle of a download the store knows neither number.
            detail = needed > 0 || available > 0 ? .noSpace(needed: needed, available: available) : nil
            // Trying again fails at once until space is freed, which Settings can do.
            secondary = .openSettings
            primary = .retry
        case .failed(let failure):
            line = .stopped
            detail = failure == .checksumMismatch ? .checksumMismatch : nil
            primary = .retry
        }
    }
}
