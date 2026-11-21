import EhCore
import Observation

/// The reader's download sheet: what it shows for where the required models stand, the time
/// left of a download, and what its buttons do to the store. Navigation (Open Settings, Keep
/// Reading) is the sheet's.
///
/// The download belongs to the store: closing the sheet does not stop it.
@Observable
public final class ReaderTranslationDownloadModel {
    @ObservationIgnored public let store: PageTranslationModelStore
    @ObservationIgnored private var pace = ReaderTranslationDownloadPace()

    /// The time left of the download, in whole minutes; `nil` while there is none to give.
    /// Set only when it changes, so a progress report does not re-render the sheet twice.
    public private(set) var timeLeft: Duration?

    public init(store: PageTranslationModelStore) {
        self.store = store
    }

    /// Reads the store's folder unless it has been read: a press of Translate reads it first.
    public func load() async {
        if !store.isLoaded { await store.refresh() }
    }

    public var content: ReaderTranslationDownloadContent {
        ReaderTranslationDownloadContent(state: store.requiredModelsState, isConnected: store.isConnected)
    }

    /// Whether a required model may be used only non-commercially; the sheet says so.
    public var includesNonCommercial: Bool { store.requiredModelsIncludeNonCommercial }

    public var isReady: Bool { store.requiredModelsState == .ready }

    /// Notes where the download stands now; called whenever the store's progress changes.
    public func noteProgress(at time: ContinuousClock.Instant = .now) {
        note(store.requiredModelsState, at: time)
    }

    func note(_ state: ModelSetState, at time: ContinuousClock.Instant) {
        let progress: ModelTransferProgress? = if case .downloading(let progress) = state { progress } else { nil }
        pace.note(progress, at: time)
        let remaining = progress.flatMap(pace.remaining)
        if remaining != timeLeft { timeLeft = remaining }
    }

    /// Does what a button asks of the store; the sheet's own actions do nothing here.
    public func perform(_ action: ReaderTranslationDownloadContent.Action) {
        switch action {
        case .download, .retry: store.downloadRequiredModels()
        case .pause: store.pause()
        case .resume: store.resume()
        case .openSettings, .keepReading: break
        }
    }
}
