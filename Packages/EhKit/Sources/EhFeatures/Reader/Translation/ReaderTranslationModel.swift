import Dependencies
import EhCore
import EhDatabase
import EhModels
import Foundation
import Observation

/// What `ReaderTranslationModel` needs of the reader that owns it.
@MainActor
protocol ReaderTranslationHost: AnyObject {
    var engine: ReaderEngineCommands? { get }
    var currentPage: Int { get }
    /// Whether the closing page after the last page is current.
    var isAtEnd: Bool { get }
    /// The address the engine shows a page's image from, once the page is resolved.
    func translationImageURL(of page: Int) -> URL?
    /// Translate was pressed and the models are not installed: the download sheet opens.
    func translationNeedsModels()
}

/// Page translation in one reader (`README` 4.1, 4.2, 7.4, 7.5 and 8).
///
/// - **Off until pressed.** A new reader is off. It creates no service and loads nothing;
///   after the first page is on screen it reads once how many pages of the gallery were
///   translated before (`pagesTranslatedBefore`, the button's mark).
/// - **A press** turns Translate on for this reader only: a session is opened, the pages
///   around the current one are asked for, and the service shows the stored ones at once
///   while the models load. Without models the press opens the download sheet and is
///   remembered by this reader: if the install ends while it is open, Translate turns on.
/// - **On** lasts until the reader closes or Translate is pressed again. Nothing about it is
///   stored. Turning it off stops the work and keeps the models. The engine is given no
///   overlay while it is off, so the pages translated earlier let their patches go; turning
///   it on again gives them back at once. Holding the original keeps them.
///
/// The only observable values are what the controls draw. The statuses and overlays of the
/// pages are not: the engine is told page by page (`ReaderEngineCommands.reloadTranslation`).
@Observable
public final class ReaderTranslationModel {
    /// Whether Translate is on in this reader.
    public private(set) var isOn = false
    /// What shows while Translate is on. A press of Translate shows `.translated`.
    public private(set) var displayMode = ReaderTranslationDisplayMode.translated
    /// Whether the original is shown while a finger holds it (Shelf's Translate button).
    public private(set) var isHoldingOriginal = false
    /// The current page's status, for the design's capsule, toast or line.
    public private(set) var status: ReaderTranslationStatus?
    /// The nearest page on screen whose translation failed while Translate is on (either page
    /// of a spread, any page of the strip that shows), or `nil`: Ledger's warning mark on its
    /// resting Translate button, whose sheet shows the status only when pulled up.
    public private(set) var failedPageOnScreen: Int?
    /// How many pages of the gallery have a stored translation for the current models, read
    /// once after the first page: the mark on the Translate button.
    public private(set) var pagesTranslatedBefore = 0
    /// Translate was pressed without models; it turns on when they are installed, as long as
    /// this reader is open.
    public private(set) var isWaitingForModels = false
    /// Whether the model store has been looked at: after the first page, or at a press.
    private var hasLookedAtStore = false

    @ObservationIgnored weak var host: ReaderTranslationHost?
    @ObservationIgnored private let gid: String
    @ObservationIgnored private let pageCount: Int
    @ObservationIgnored private var session: PageTranslationSession?
    /// The window last sent to the session.
    @ObservationIgnored private var sentWindow = PageTranslationWindow.empty
    /// The service's statuses of the pages in `sentWindow`.
    @ObservationIgnored private var statuses: [Int: PageTranslationStatus] = [:]
    /// Every page translated in this reader, also those that left the window: the engine asks
    /// for a page's overlay when it makes the page's view. Kept while Translate is off, when
    /// the engine is given none of them.
    @ObservationIgnored private var overlays: [Int: PageTranslationOverlay] = [:]
    /// Pages whose overlay the engine could not show and which were drawn again for it. A
    /// second failure is not drawn again by itself: the page is marked failed, with Retry.
    @ObservationIgnored private var redrawnPages: Set<Int> = []
    /// Pages marked failed because their overlay could not be shown after it was drawn again.
    /// The service still has them as translated, so their failure is the reader's own.
    @ObservationIgnored private var unshownPages: Set<Int> = []
    /// The pages the engine shows, nearest first: two in a spread, several in the strip.
    /// Empty until the engine has said.
    @ObservationIgnored private var pagesOnScreen: [Int] = []
    /// Where the compare wipe's line is across the reader, from 0 to 1. Kept when the display
    /// changes, so the wipe comes back where it was left. Not observable: it follows a finger.
    @ObservationIgnored public private(set) var compareFraction = 0.5
    /// What the engine was last told to show.
    @ObservationIgnored private var sentDisplay = ReaderTranslationDisplay.original
    @ObservationIgnored private var isClosed = false
    @ObservationIgnored private var countTask: Task<Void, Never>?
    @ObservationIgnored private var pressTask: Task<Void, Never>?
    @ObservationIgnored private var installWatch: Task<Void, Never>?
    @ObservationIgnored private var eventsTask: Task<Void, Never>?

    // Each is made on its first read: the store after the first page, the service at a press.
    @ObservationIgnored @Dependency(\.pageTranslation) private var pageTranslation
    @ObservationIgnored @Dependency(\.pageTranslationModelStore) private var store
    @ObservationIgnored @Dependency(\.database) private var database

    /// Cheap: it reads nothing and creates nothing.
    init(gid: String, pageCount: Int) {
        self.gid = gid
        self.pageCount = pageCount
    }

    // MARK: What the controls read

    /// The availability for a gallery that is not marked as another language. Until the
    /// store has read its folder, installed models cannot be told from missing ones; the
    /// reader then says `.ready`, and a press reads the folder before it decides.
    func availability(isOtherLanguage: Bool) -> ReaderTranslationAvailability {
        if isOtherLanguage { return .unavailable }
        guard hasLookedAtStore, store.isLoaded else { return .ready }
        return ReaderTranslationAvailability(store.requiredModelsState)
    }

    /// What the engine shows over its pages now.
    public var display: ReaderTranslationDisplay {
        guard isOn, !isHoldingOriginal else { return .original }
        return switch displayMode {
        case .original: .original
        case .translated: .translated
        case .compare: .compare(fraction: compareFraction)
        }
    }

    /// The overlay of a translated page, or `nil`; `nil` for every page while Translate is
    /// off. The engine asks when it makes a page's view and when it is told that the page's
    /// translation changed.
    public func overlay(at page: Int) -> PageTranslationOverlay? {
        isOn ? overlays[page] : nil
    }

    // MARK: What the controls do

    /// Translate: on when it is off (or the download sheet when there are no models), off
    /// when it is on.
    func press() {
        guard !isClosed else { return }
        if isOn {
            turnOff()
            return
        }
        guard pressTask == nil else { return }
        pressTask = Task { [weak self] in
            await self?.pressed()
            self?.pressTask = nil
        }
    }

    public func setDisplayMode(_ mode: ReaderTranslationDisplayMode) {
        guard displayMode != mode else { return }
        displayMode = mode
        sendDisplay()
    }

    /// Shows the original while `isHeld` (Shelf: holding Translate).
    public func holdOriginal(_ isHeld: Bool) {
        guard isHoldingOriginal != isHeld else { return }
        isHoldingOriginal = isHeld
        sendDisplay()
    }

    /// Where the compare wipe is, from 0 to 1. Not observable: it follows a finger.
    public func setCompareFraction(_ fraction: Double) {
        compareFraction = min(max(fraction, 0), 1)
        sendDisplay()
    }

    /// Retry of the current page's failure.
    func retryCurrentPage() {
        guard isOn, let page = host?.currentPage, status == .failed(page: page) else { return }
        unshownPages.remove(page)
        // Until the service says more: the page is asked for again.
        statuses[page] = .translating
        session?.retry(page)
        refreshStatus()
    }

    /// The engine could not read a page's patch file. The first time, the service draws it
    /// again. When the drawing again cannot be shown either, the page is marked failed: it
    /// shows the original, and so does its status, until Retry.
    func overlayDidFail(page: Int) {
        guard overlays.removeValue(forKey: page) != nil else { return }
        host?.engine?.reloadTranslation(page)
        if redrawnPages.insert(page).inserted {
            session?.retry(page)
        } else {
            unshownPages.insert(page)
            refreshStatus()
        }
    }

    // MARK: What the reader forwards

    /// The first page is on screen: the one read of the mark's count. Not for a gallery in
    /// another language, which shows no Translate control.
    func firstPageDidShow(isOtherLanguage: Bool) {
        guard !hasLookedAtStore, !isClosed, !isOtherLanguage else { return }
        hasLookedAtStore = true
        countTask = Task { [weak self] in await self?.readCount() }
    }

    func currentPageDidChange() {
        sendWindow()
        refreshStatus()
    }

    /// The engine shows other pages: the other page of a spread, or another part of the
    /// strip. Nothing is asked while Translate is off.
    func pagesOnScreenDidChange(_ pages: [Int]) {
        guard pages != pagesOnScreen else { return }
        pagesOnScreen = pages
        defer { refreshStatus() }
        // Pages without the current page are those of a turn, and the engine names the new
        // current page next: the window is sent then, once, not twice.
        guard let host, pages.contains(host.currentPage) else { return }
        sendWindow()
    }

    /// A page's image address became known or changed.
    func pageDidResolve(_ page: Int) {
        guard isOn, window(at: host?.currentPage ?? 0).pages.contains(page) else { return }
        sendWindow()
    }

    /// The closing page became current or stopped being current. `currentPage` stays the last
    /// page meanwhile, so the window does not change: nothing more is asked for there.
    func atEndDidChange() {
        refreshStatus()
    }

    /// The reader closed: everything stops, and a press that waits for models is forgotten.
    func close() {
        guard !isClosed else { return }
        isClosed = true
        for task in [countTask, pressTask, installWatch, eventsTask] { task?.cancel() }
        isWaitingForModels = false
        session?.close()
        session = nil
    }

    // MARK: Turning on and off

    private func pressed() async {
        hasLookedAtStore = true
        let store = store
        if !store.isLoaded { await store.refresh() }
        guard !isClosed else { return }
        if store.requiredModelsState == .ready {
            turnOn()
        } else {
            isWaitingForModels = true
            watchInstall()
            host?.translationNeedsModels()
        }
    }

    /// Turns Translate on once the models are installed, if this reader is still open then.
    private func watchInstall() {
        guard installWatch == nil else { return }
        let store = store
        installWatch = Task { [weak self] in
            await forEachObservedValue(of: { store.requiredModelsState == .ready }) { isReady in
                guard isReady, let self, self.isWaitingForModels, !self.isClosed else { return }
                self.isWaitingForModels = false
                self.installWatch?.cancel()
                self.installWatch = nil
                self.turnOn()
            }
        }
    }

    private func turnOn() {
        guard !isClosed, !isOn else { return }
        isOn = true
        displayMode = .translated
        if session == nil { openSession() }
        sendWindow()
        sendDisplay()
        // The pages translated before Translate was last turned off show again at once.
        reloadOverlays()
        refreshStatus()
    }

    private func turnOff() {
        isOn = false
        isHoldingOriginal = false
        sentWindow = .empty
        statuses = [:]
        unshownPages = []
        session?.setWindow(.empty)
        sendDisplay()
        // The engine cannot tell off from the original chosen: it is given no overlay, so the
        // page views let their patches go.
        reloadOverlays()
        refreshStatus()
    }

    /// Asks the engine again for every page translated in this reader. A page without a view
    /// costs nothing.
    private func reloadOverlays() {
        guard let engine = host?.engine else { return }
        for page in overlays.keys.sorted() { engine.reloadTranslation(page) }
    }

    private func openSession() {
        let session = pageTranslation.openSession(gid)
        self.session = session
        // Only the events: a task that held the session would keep it open after the reader
        // was let go.
        let events = session.events
        eventsTask = Task { [weak self] in
            for await event in events {
                self?.handle(event)
            }
        }
    }

    // MARK: The service

    private func sendWindow() {
        guard isOn, let session, let host else { return }
        let window = window(at: host.currentPage).request(imageURL: host.translationImageURL(of:))
        guard window != sentWindow else { return }
        sentWindow = window
        let wanted = Set(window.pages.map(\.index))
        statuses = statuses.filter { wanted.contains($0.key) }
        session.setWindow(window)
    }

    private func window(at page: Int) -> ReaderTranslationWindow {
        ReaderTranslationWindow(currentPage: page, pageCount: pageCount, shown: pagesOnScreen)
    }

    private func handle(_ event: PageTranslationEvent) {
        guard !isClosed else { return }
        let page = event.pageIndex
        switch event.status {
        case .translated(let overlay):
            if overlays[page] != overlay {
                overlays[page] = overlay
                // While off the engine is given nothing; turning on gives it every overlay.
                if isOn { host?.engine?.reloadTranslation(page) }
            }
        case .nothingToDraw, .skipped, .failed:
            if overlays.removeValue(forKey: page) != nil {
                host?.engine?.reloadTranslation(page)
            }
        case .loadingModels, .translating:
            break
        }
        // A late event of a page that left the window, or of a reader that turned it off.
        guard isOn, sentWindow.pages.contains(where: { $0.index == page }) else { return }
        statuses[page] = event.status
        // Retry was asked for elsewhere, or the page is drawn again: the service has the say.
        unshownPages.remove(page)
        if page == host?.currentPage || pagesOnScreen.contains(page) { refreshStatus() }
    }

    private func refreshStatus() {
        var new: ReaderTranslationStatus?
        var failed: Int?
        if isOn, let host, !host.isAtEnd {
            let page = host.currentPage
            new = pageStatus(of: page)
            // Mid-turn the engine names its new pages before the new current page: until it
            // does, only the current page counts.
            let shown = pagesOnScreen.contains(page) ? pagesOnScreen : [page]
            failed = shown.first { pageStatus(of: $0) == .failed(page: $0) }
        }
        if status != new { status = new }
        if failedPageOnScreen != failed { failedPageOnScreen = failed }
    }

    private func pageStatus(of page: Int) -> ReaderTranslationStatus? {
        if unshownPages.contains(page) { return .failed(page: page) }
        return statuses[page].flatMap { ReaderTranslationStatus($0, page: page) }
    }

    private func sendDisplay() {
        let display = display
        guard display != sentDisplay else { return }
        sentDisplay = display
        host?.engine?.setTranslationDisplay(display)
    }

    private func readCount() async {
        // The store is made here, not before: it opens the download session. It reads no
        // folder; which models the choices resolve to needs none.
        guard let key = store.resolvedModelSet?.key else { return }
        let count = (try? await database.pageTranslationCount(gid: gid, modelSetKey: key)) ?? 0
        guard !isClosed, count != pagesTranslatedBefore else { return }
        pagesTranslatedBefore = count
    }
}
