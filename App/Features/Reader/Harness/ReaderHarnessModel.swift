#if DEBUG || HARNESS
import EhFeatures
import Observation
import QuartzCore
import SwiftUI
import UIKit

/// The host side of the reader harness: a made-up gallery whose page URLs "resolve" after a
/// delay and sometimes fail, so every state of the engine can be reached by hand.
///
/// Page states live outside observation on purpose. The engine asks for them when it needs
/// them and is told about changes page by page through the proxy, which is exactly how the real
/// reader model is meant to drive it.
///
/// A scripted run (`ReaderHarnessRun`) gives it a recorder: every question of the engine and
/// everything the engine reports is then written down, and pages resolve after a fixed delay
/// instead of a random one, so that two runs can be compared.
@Observable
final class ReaderHarnessModel: ReaderEngineDataSource, ReaderEngineDelegate {
    var configuration = ReaderConfiguration()
    private(set) var galleryPageCount = 60
    private(set) var currentPage = 1
    /// Whether the closing page's stand-in is what the reader is on.
    private(set) var isAtEnd = false
    var isPanelVisible = true
    /// Seconds a page takes to resolve its URL, and again to download its image.
    var latency = 0.8
    /// Whether the stand-in for the closing page follows the last page.
    var hasClosingPage = false {
        didSet {
            if hasClosingPage != oldValue {
                proxy.reloadData()
            }
        }
    }
    /// Whether the host hands the engine aspect ratios before the images load.
    var knowsAspectRatios = false {
        didSet {
            if knowsAspectRatios != oldValue {
                proxy.reloadData()
            }
        }
    }
    /// Seconds between automatic page turns; 0 is off.
    var autoAdvanceInterval = 0.0 {
        didSet { restartAutoAdvance() }
    }
    private(set) var events: [String] = []

    @ObservationIgnored let proxy = ReaderEngineProxy()
    @ObservationIgnored let recorder: ReaderHarnessRecorder?
    /// Milliseconds from `markOpened()` to the first image the engine reported.
    @ObservationIgnored private(set) var firstPageShownAfter: Double?
    @ObservationIgnored private var openedAt = CACurrentMediaTime()
    /// Pages whose image the engine reported as loaded or failed.
    @ObservationIgnored private var reported: Set<Int> = []
    /// In a recorded run, the script's mark the engine asked for the closing page after.
    @ObservationIgnored private(set) var trailerMadeAfter: String?
    @ObservationIgnored private var states: [Int: ReaderPageState] = [:]
    @ObservationIgnored private var resolving: [Int: Task<Void, Never>] = [:]
    @ObservationIgnored private var attempts: [Int: Int] = [:]
    @ObservationIgnored private var autoAdvance: Task<Void, Never>?
    /// Fresh URLs every time the harness opens, so images download again instead of coming
    /// from the disk cache.
    @ObservationIgnored private let session = UUID().uuidString.prefix(8).lowercased()

    init(recorder: ReaderHarnessRecorder? = nil) {
        self.recorder = recorder
        ReaderHarnessURLProtocol.install()
        if let recorder {
            proxy.trace = { recorder.add($0) }
        }
    }

    /// A scripted run's gallery: its settings in place before the engine exists.
    convenience init(run: ReaderHarnessRun, recorder: ReaderHarnessRecorder) {
        self.init(recorder: recorder)
        configuration = run.configuration
        galleryPageCount = run.pageCount
        currentPage = run.startPage
        latency = run.latency
        knowsAspectRatios = run.knowsAspectRatios
        hasClosingPage = run.hasClosingPage
        isPanelVisible = false
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
        proxy.reloadData()
    }

    /// The engine's view is about to be made: "first page shown" counts from here.
    func markOpened() {
        openedAt = CACurrentMediaTime()
    }

    /// Whether nothing more is expected for a page that has a view: it is resolved (or nobody
    /// is resolving it), and its image has loaded or failed.
    func isSettled(_ page: Int) -> Bool {
        switch states[page] ?? .pending {
        case .pending: resolving[page] == nil
        case .failed: true
        case .image: reported.contains(page)
        }
    }

    func clearImageCache() {
        ImagePipeline.cache.clearCache()
        log("image cache cleared")
    }

    func stop() {
        autoAdvance?.cancel()
        resolving.values.forEach { $0.cancel() }
    }

    /// Resolution fails once for every seventh page; the image fails once for every eleventh.
    static func failsResolutionFirst(_ page: Int) -> Bool { page % 7 == 0 }
    static func failsImageFirst(_ page: Int) -> Bool { page % 11 == 0 }

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
        return hasClosingPage
    }

    func makeTrailerViewController() -> UIViewController? {
        recorder?.add("D makeTrailer")
        if let recorder {
            let mark = recorder.lines.last { $0.hasPrefix("M ") }
            trailerMadeAfter = mark.map { String($0.dropFirst(2)) } ?? "(before the first mark)"
        }
        log("closing page made on page \(currentPage)")
        let host = UIHostingController(rootView: ReaderHarnessClosingPage(model: self))
        host.view.backgroundColor = .clear
        return host
    }

    /// A control of the closing page's stand-in fired.
    func closingPageButtonTapped(_ name: String) {
        log("closing page: \(name)")
        if recorder != nil {
            ReaderHarnessLog.line("closing page: \(name)")
        }
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
        reported.remove(page)
        attempts[page, default: 0] += 1
        states[page] = .pending
        proxy.reloadPage(page)
        resolve(page)
    }

    func readerDidLoadImage(page: Int, pixelSize: CGSize) {
        recorder?.add("E loaded \(page) \(Int(pixelSize.width))x\(Int(pixelSize.height))")
        log("loaded page \(page) at \(Int(pixelSize.width))×\(Int(pixelSize.height))")
        reported.insert(page)
        if firstPageShownAfter == nil {
            firstPageShownAfter = (CACurrentMediaTime() - openedAt) * 1_000
        }
    }

    func readerDidFailToLoadImage(page: Int) {
        recorder?.add("E failed \(page)")
        log("image of page \(page) failed")
        reported.insert(page)
    }

    func readerDidTapToTogglePanel() {
        recorder?.add("E panel")
        isPanelVisible.toggle()
    }

    func readerDidChangeTrailerVisibility(_ isCurrent: Bool) {
        recorder?.add("E trailer \(isCurrent)")
        log(isCurrent ? "on the closing page" : "left the closing page")
        isAtEnd = isCurrent
    }

    func readerContextMenu(for page: Int) -> UIMenu? {
        typealias Strings = L10n.Localizable.ReadingView.ContextMenu.Button
        var actions = [
            UIAction(title: Strings.reload, image: UIImage(systemName: "arrow.counterclockwise")) { [weak self] _ in
                self?.readerDidRequestRetry(page: page)
            }
        ]
        if case .image(let url) = pageState(at: page) {
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

    // MARK: Private

    private func resolve(_ page: Int) {
        guard resolving[page] == nil else { return }
        // A recorded run is compared with another: its pages take the same time every time.
        let delay = recorder == nil ? latency * Double.random(in: 0.5...1.5) : latency
        resolving[page] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }
            resolving[page] = nil
            let attempt = attempts[page, default: 0]
            if Self.failsResolutionFirst(page), attempt == 0 {
                states[page] = .failed
            } else if let url = ReaderHarnessURLProtocol.url(
                forPage: page, session: session, attempt: attempt, latency: latency,
                fails: Self.failsImageFirst(page) && attempt == 0
            ) {
                states[page] = .image(url)
            } else {
                states[page] = .failed
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
