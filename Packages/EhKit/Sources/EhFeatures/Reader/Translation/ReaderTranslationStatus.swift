import EhCore

/// What the current page's translation control says (`README` 7.5). `nil` on the model
/// while Translate is off, on the closing page, before the service has said anything about
/// the page, and for an animated page, which is never translated.
nonisolated public enum ReaderTranslationStatus: Hashable, Sendable {
    /// The models are loading ("Getting translation ready…"). The page may already show its
    /// translation from an earlier reader; then the status is `.translated` instead.
    case gettingReady
    /// Waiting for its turn or in work ("Translating page 23…").
    case translating(page: Int)
    /// The page shows its translation (the target language, and how to see the original).
    case translated
    /// Done, and nothing was found to translate: the page shows the original.
    case nothingToDraw
    /// "Couldn't translate page 23", with Retry (`ReaderModel.retryTranslation()`).
    case failed(page: Int)

    /// The control's status for a page's status in the service, or `nil` for none.
    init?(_ status: PageTranslationStatus, page: Int) {
        switch status {
        case .loadingModels: self = .gettingReady
        case .translating: self = .translating(page: page)
        case .translated: self = .translated
        case .nothingToDraw: self = .nothingToDraw
        case .failed: self = .failed(page: page)
        case .skipped: return nil
        }
    }
}

/// How the reader shows its pages while Translate is on (`README` 7.4). Each design drives it
/// with its own controls: Shelf's hold, Wall's pill, Ledger's segmented control.
nonisolated public enum ReaderTranslationDisplayMode: Hashable, Sendable, CaseIterable {
    /// The page as the site sent it. Translation goes on, so switching back is instant.
    case original
    /// What a press of Translate shows.
    case translated
    /// The overlay masked at a line the finger drags (Wall's wipe, Ledger's Compare; MT17).
    case compare
}

/// What the engine is told to show over its pages: `ReaderEngineCommands.setTranslationDisplay`.
nonisolated public enum ReaderTranslationDisplay: Hashable, Sendable {
    /// No overlay: Translate is off, the original is chosen or held.
    case original
    case translated
    /// The overlay shows on one side of the wipe; `fraction` is its place across the page,
    /// from 0 to 1.
    case compare(fraction: Double)
}
