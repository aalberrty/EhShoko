#if DEBUG || HARNESS
import EhFeatures
import EhModels
import Observation
import QuartzCore
import UIKit

/// The host side of the reader harness: a made-up gallery whose page URLs "resolve" after a
/// delay and sometimes fail, so every state of the engine can be reached by hand.
///
/// Page states live outside observation on purpose. The engine asks for them when it needs
/// them and is told about changes page by page through the proxy, which is exactly how the real
/// reader model is meant to drive it.
///
/// With a recorder attached, every call the engine makes is written down
/// (`ReaderHarnessRecorder`). That is why what the engine asks (`pageCount`, `hasTrailer`) is
/// kept apart from what the harness's own views read (`galleryPageCount`, `showsClosingSlot`).
@Observable
final class ReaderHarnessModel: ReaderEngineDataSource, ReaderEngineDelegate {
    var configuration: ReaderConfiguration
    private(set) var galleryPageCount: Int
    private(set) var currentPage: Int
    /// Whether the reader is on the closing page's slot.
    private(set) var isAtEnd = false
    var isPanelVisible: Bool
    /// Seconds a page takes to resolve its URL, and again to download its image.
    var latency: Double
    /// Whether the host hands the engine aspect ratios before the images load.
    var knowsAspectRatios: Bool {
        didSet {
            if knowsAspectRatios != oldValue {
                proxy.reloadData()
            }
        }
    }
    /// Whether a slot for the closing page follows the last page. It holds the closing page,
    /// or the stand-in where the setup asks for it (`ReaderHarnessSetup.slotContent`).
    var showsClosingSlot: Bool {
        didSet {
            if showsClosingSlot != oldValue {
                proxy.reloadData()
            }
        }
    }
    /// Makes the stand-in ask for more height, which the vertical strip then gives it.
    var isStandInTall = false
    /// How often each control of the stand-in was tapped.
    private(set) var standInTaps: [String: Int] = [:]
    /// The look of the page status views and the closing page; `nil`: the app's.
    var look: Look?
    /// What the gallery shows of its made-up translation (`ReaderHarnessTranslation.swift`).
    var translationMode = ReaderHarnessTranslationMode.off {
        didSet {
            if translationMode != oldValue {
                translationModeDidChange()
            }
        }
    }
    /// Seconds between automatic page turns; 0 is off.
    var autoAdvanceInterval = 0.0 {
        didSet { restartAutoAdvance() }
    }
    private(set) var events: [String] = []

    @ObservationIgnored let setup: ReaderHarnessSetup
    @ObservationIgnored let proxy = ReaderEngineProxy()
    @ObservationIgnored var recorder: ReaderHarnessRecorder?
    /// The made-up translation; `nil` until Translate is "pressed".
    @ObservationIgnored var translation: ReaderHarnessTranslation?
    /// The pages the engine last said the reader is on.
    @ObservationIgnored var pagesOnScreen: [Int] = []
    /// Seconds from this model's creation to the first image the engine reported.
    @ObservationIgnored private(set) var firstPageDelay: Double?
    /// Seconds it took to make the slot's controller, once the engine has asked for it.
    @ObservationIgnored private(set) var trailerMakeDuration: Double?
    @ObservationIgnored private let createdAt = CACurrentMediaTime()
    @ObservationIgnored private var states: [Int: ReaderPageState] = [:]
    @ObservationIgnored private var resolving: [Int: Task<Void, Never>] = [:]
    @ObservationIgnored private var attempts: [Int: Int] = [:]
    /// Pages whose image the engine reported as loaded or failed.
    @ObservationIgnored private var reported: Set<Int> = []
    /// Pages whose URL did not resolve or whose image did not load, until they are retried.
    @ObservationIgnored private var failedPages: Set<Int> = []
    @ObservationIgnored private var autoAdvance: Task<Void, Never>?
    /// Fresh URLs every time the harness opens, so images download again instead of coming
    /// from the disk cache.
    @ObservationIgnored private let session = UUID().uuidString.prefix(8).lowercased()

    /// `translation`: a translation made ahead. The reader then opens with Translate on, so
    /// the engine is told what to show before it exists.
    init(setup: ReaderHarnessSetup = ReaderHarnessSetup(), translation: ReaderHarnessTranslation? = nil) {
        self.setup = setup
        configuration = setup.configuration
        galleryPageCount = setup.pageCount
        currentPage = setup.startPage
        isPanelVisible = setup.showsPanel
        latency = setup.latency
        knowsAspectRatios = setup.knowsAspectRatios
        showsClosingSlot = setup.hasTrailer
        look = setup.look
        ReaderHarnessURLProtocol.install()
        if let translation {
            self.translation = translation
            translationMode = .translated
            proxy.setTranslationDisplay(.translated)
        }
    }

    // MARK: Controls

    func setPageCount(_ count: Int) {
        guard count != galleryPageCount else { return }
        galleryPageCount = count
        resetPages()
    }

    /// Forgets every resolved URL, like the legacy "reload all images".
    func resetPages() {
        resolving.values.forEach { $0.cancel() }
        resolving = [:]
        states = [:]
        attempts = [:]
        reported = []
        failedPages = []
        proxy.reloadData()
    }

    func clearImageCache() {
        ImagePipeline.cache.clearCache()
        log("image cache cleared")
    }

    func stop() {
        translation?.stop()
        autoAdvance?.cancel()
        resolving.values.forEach { $0.cancel() }
    }

    func standInWasTapped(_ control: String) {
        standInTaps[control, default: 0] += 1
        log("closing page: \(control)")
        ReaderHarnessFiles.log("\(setup.name): stand-in control \(control) tapped")
    }

    /// Resolution fails once for every seventh page; the image fails once for every eleventh.
    static func failsResolutionFirst(_ page: Int) -> Bool { page % 7 == 0 }
    static func failsImageFirst(_ page: Int) -> Bool { page % 11 == 0 }

    private func failsResolution(_ page: Int, attempt: Int) -> Bool {
        setup.failingPages.map { $0.resolution.contains(page) } ?? (Self.failsResolutionFirst(page) && attempt == 0)
    }

    private func failsImage(_ page: Int, attempt: Int) -> Bool {
        setup.failingPages.map { $0.image.contains(page) } ?? (Self.failsImageFirst(page) && attempt == 0)
    }

    /// Whether nothing more is expected for a page that has a view: it is resolved, or nobody
    /// is resolving it, and its image has loaded or failed.
    func isSettled(_ page: Int) -> Bool {
        switch states[page] ?? .pending {
        case .pending: resolving[page] == nil
        case .failed: true
        case .image: reported.contains(page)
        }
    }

    // MARK: ReaderEngineDataSource

    var pageCount: Int {
        recorder?.add("D pageCount")
        return galleryPageCount
    }

    func pageState(at page: Int) -> ReaderPageState {
        recorder?.add("D pageState \(page)")
        return states[page] ?? .pending
    }

    func aspectRatio(at page: Int) -> CGFloat? {
        recorder?.add("D aspect \(page)")
        return knowsAspectRatios ? ReaderHarnessImages.spec(forPage: page).aspectRatio : nil
    }

    var hasTrailer: Bool {
        recorder?.add("D hasTrailer")
        return showsClosingSlot
    }

    // The two members for the page status views are not recorded: they are not page calls,
    // and a record must stay comparable with one made before they existed.

    /// The harness's pages fail as if the site could not be reached.
    func failureReason(at page: Int) -> AppError? {
        states[page] == .failed ? .networkingFailed : nil
    }

    var failedPageCount: Int { failedPages.count }

    /// The closing page, with a detail model of its own whose requests are counted in the log
    /// (`ReaderClosingHarness`), or the stand-in where the setup asks for it.
    func makeTrailerViewController() -> UIViewController? {
        recorder?.add("D makeTrailer")
        let started = CACurrentMediaTime()
        let name = setup.name
        let controller = switch setup.slotContent {
        case .standIn:
            ReaderHarnessStandIn.makeController(model: self)
        case .closingPage:
            ReaderClosingHarness.makeController(pageCount: galleryPageCount) { line in
                ReaderHarnessFiles.log("\(name): \(line)")
            }
        }
        let duration = CACurrentMediaTime() - started
        trailerMakeDuration = duration
        log(String(format: "closing page made in %.1f ms, on page %d", duration * 1_000, currentPage))
        return controller
    }

    // MARK: ReaderEngineDelegate

    func readerDidChangeCurrentPage(_ page: Int) {
        recorder?.add("E page \(page)")
        currentPage = page
    }

    func readerNeedsPages(_ pages: [Int]) {
        recorder?.add("E needs " + pages.map(String.init).joined(separator: ","))
        for page in pages where (states[page] ?? .pending) == .pending {
            resolve(page)
        }
    }

    func readerNoLongerNeedsPages(_ pages: [Int]) {
        recorder?.add("E release " + pages.map(String.init).joined(separator: ","))
        for page in pages {
            resolving.removeValue(forKey: page)?.cancel()
        }
    }

    func readerDidRequestRetry(page: Int) {
        recorder?.add("E retry \(page)")
        log("retry page \(page)")
        retry(page)
    }

    func readerDidRequestRetryAllFailed() {
        recorder?.add("E retry all failed")
        log("retry \(failedPages.count) failed pages")
        for page in failedPages.sorted() {
            retry(page)
        }
    }

    func readerDidLoadImage(page: Int, pixelSize: CGSize) {
        recorder?.add("E loaded \(page) \(Int(pixelSize.width))x\(Int(pixelSize.height))")
        reported.insert(page)
        failedPages.remove(page)
        if firstPageDelay == nil {
            let delay = CACurrentMediaTime() - createdAt
            firstPageDelay = delay
            ReaderHarnessFiles.log(String(
                format: "%@: first page shown after %.0f ms (page %d)", setup.name, delay * 1_000, page
            ))
        }
        log("loaded page \(page) at \(Int(pixelSize.width))×\(Int(pixelSize.height))")
    }

    func readerDidFailToLoadImage(page: Int) {
        recorder?.add("E failed \(page)")
        reported.insert(page)
        failedPages.insert(page)
        log("image of page \(page) failed")
    }

    func readerDidTapToTogglePanel() {
        recorder?.add("E panel")
        ReaderHarnessFiles.log("\(setup.name): panel toggled")
        isPanelVisible.toggle()
    }

    func readerContextMenu(for page: Int) -> UIMenu? {
        typealias Strings = L10n.Localizable.ReadingView.ContextMenu.Button
        var actions = [
            UIAction(title: Strings.reload, image: UIImage(systemName: "arrow.counterclockwise")) { [weak self] _ in
                self?.readerDidRequestRetry(page: page)
            }
        ]
        if case .image(let url) = states[page] {
            let entries = [
                (Strings.copy, "plus.square.on.square"),
                (Strings.save, "square.and.arrow.down"),
                (Strings.saveOriginal, "square.and.arrow.down.on.square"),
                (Strings.share, "square.and.arrow.up")
            ]
            actions += entries.map { title, symbol in
                UIAction(title: title, image: UIImage(systemName: symbol)) { [weak self] _ in
                    self?.reportOriginal(of: url, page: page, action: title)
                }
            }
        }
        return UIMenu(children: actions)
    }

    func readerDidChangeTrailerVisibility(_ isCurrent: Bool) {
        recorder?.add("E trailer \(isCurrent)")
        ReaderHarnessFiles.log("\(setup.name): closing page \(isCurrent ? "current" : "away"), page \(currentPage)")
        isAtEnd = isCurrent
    }

    // MARK: Private

    private func retry(_ page: Int) {
        reported.remove(page)
        failedPages.remove(page)
        attempts[page, default: 0] += 1
        states[page] = .pending
        proxy.reloadPage(page)
        resolve(page)
    }

    private func resolve(_ page: Int) {
        guard resolving[page] == nil else { return }
        let delay = setup.hasFixedLatency ? latency : latency * Double.random(in: 0.5...1.5)
        resolving[page] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }
            resolving[page] = nil
            let attempt = attempts[page, default: 0]
            if failsResolution(page, attempt: attempt) {
                states[page] = .failed
            } else if let url = ReaderHarnessURLProtocol.url(
                forPage: page, session: session, attempt: attempt, latency: setup.downloadLatency ?? latency,
                fails: failsImage(page, attempt: attempt)
            ) {
                states[page] = .image(url)
            } else {
                states[page] = .failed
            }
            if states[page] == .failed {
                failedPages.insert(page)
            }
            proxy.reloadPage(page)
        }
    }

    /// Shows that the untouched original is still on disk for the host to save or share.
    private func reportOriginal(of url: URL, page: Int, action: String) {
        Task { [weak self] in
            let bytes = await ImagePipeline.storedOriginalData(for: url)?.count
            self?.log("\(action) page \(page): original " + (bytes.map { "\($0 / 1_024) KB on disk" } ?? "missing"))
        }
    }

    private func restartAutoAdvance() {
        autoAdvance?.cancel()
        autoAdvance = nil
        let interval = autoAdvanceInterval
        guard interval > 0 else { return }
        autoAdvance = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled, let self else { return }
                if !proxy.advance() {
                    autoAdvanceInterval = 0
                    return
                }
            }
        }
    }

    private func log(_ event: String) {
        events.append(event)
        if events.count > 4 {
            events.removeFirst(events.count - 4)
        }
    }
}
#endif
