import EhCore

/// What `ReaderTranslationModel` knows of each page in its window: the service's statuses,
/// and the reader's own failures of pages whose overlay could not be shown. From them it
/// gives the controls' status.
nonisolated struct ReaderTranslationPageStatuses: Equatable {
    /// The service's statuses of the pages in the window last sent.
    private var statuses: [Int: PageTranslationStatus] = [:]
    /// Pages whose overlay the engine could not show and which were drawn again for it. A
    /// second failure is not drawn again by itself: the page is marked failed, with Retry.
    /// Kept for the reader's life, also while Translate is off.
    private var redrawnPages: Set<Int> = []
    /// Pages marked failed because their overlay could not be shown after it was drawn again.
    /// The service still has them as translated, so their failure is the reader's own.
    private var unshownPages: Set<Int> = []

    /// The service said something of a page in the window. It has the say over the reader's
    /// own failure: Retry was asked for elsewhere, or the page is drawn again.
    mutating func record(_ status: PageTranslationStatus, of page: Int) {
        statuses[page] = status
        unshownPages.remove(page)
    }

    /// A new window: the statuses of the pages that left it are forgotten.
    mutating func keep(only pages: Set<Int>) {
        statuses = statuses.filter { pages.contains($0.key) }
    }

    /// The page is asked for again (Retry): in work until the service says more.
    mutating func askAgain(_ page: Int) {
        unshownPages.remove(page)
        statuses[page] = .translating
    }

    /// The engine could not show the page's overlay. `true` the first time, when it is to be
    /// drawn again; after that the page is marked failed and `false`.
    mutating func overlayDidFail(page: Int) -> Bool {
        if redrawnPages.insert(page).inserted { return true }
        unshownPages.insert(page)
        return false
    }

    /// Translate was turned off. Which pages were drawn again is kept.
    mutating func clear() {
        statuses = [:]
        unshownPages = []
    }

    /// A page's status for the controls, or `nil` while there is none.
    func status(of page: Int) -> ReaderTranslationStatus? {
        if unshownPages.contains(page) { return .failed(page: page) }
        return statuses[page].flatMap { ReaderTranslationStatus($0, page: page) }
    }

    /// Whether the page has failed, by the service or by the reader.
    func hasFailed(_ page: Int) -> Bool {
        status(of: page) == .failed(page: page)
    }

    /// The controls' status and the nearest failed page on screen, for `current` and the
    /// pages on screen nearest first. Mid-turn the engine names its new pages before the new
    /// current page: until it does (`onScreen` without `current`), only the current page counts.
    func summary(current: Int, onScreen: [Int]) -> (status: ReaderTranslationStatus?, failedOnScreen: Int?) {
        let shown = onScreen.contains(current) ? onScreen : [current]
        return (status(of: current), shown.first(where: hasFailed))
    }
}
