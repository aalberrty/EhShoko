#if DEBUG || HARNESS
import Dependencies
import EhCore
import EhModels
import Foundation
import Observation

/// The list harness: synthetic galleries for the list under test, the scripted scroll, and
/// the result of the last run, shown on screen and written to
/// `Library/Caches/ListHarness/result.json` for `measure.sh`.
@Observable
final class ListHarnessModel {
    enum Phase: Equatable {
        case preparing
        case ready
        /// A hand is scrolling the list and the harness is watching (`-HarnessObserve`).
        case observing
        case running
        case finished(ListHarnessResult)
        case failed(String)
    }

    var options: ListHarnessOptions {
        didSet { applyOptions(from: oldValue) }
    }
    private(set) var galleries: [Gallery] = []
    private(set) var phase = Phase.preparing
    /// Which build of the list this is: every run after the first of an automatic series
    /// builds the list again, from the top, as a new launch would.
    private(set) var listID = 0

    /// The settings the list designs read, kept apart from the user's.
    @ObservationIgnored let settings: SettingsStore
    @ObservationIgnored let scroller = ListHarnessScroller()
    /// New cover URLs on every launch of the harness, and on every run of a series, so covers
    /// are downloaded and decoded.
    @ObservationIgnored private var session = ListHarnessModel.newSession()
    /// `CoverDecodeCounter` and the covers served when the run's list was built, so a run
    /// reports only its own.
    @ObservationIgnored private var coverDecodesAtStart = 0
    @ObservationIgnored private var coversServedAtStart = 0
    /// The results of an automatic series so far, written together.
    @ObservationIgnored private var results: [ListHarnessResult] = []
    @ObservationIgnored private var observer: ListHarnessObserver?
    @ObservationIgnored private var lastSave: Task<Void, Never>?
    @ObservationIgnored @Dependency(\.imageCacheClient) private var imageCache

    private static let settingsSuite = "app.ehshoko.list-harness"

    init(options: ListHarnessOptions) {
        self.options = options
        let defaults = UserDefaults(suiteName: Self.settingsSuite) ?? .standard
        defaults.removePersistentDomain(forName: Self.settingsSuite)
        settings = SettingsStore(defaults: defaults)
    }

    /// Builds the galleries and gets the cover server and the image cache ready. Call from the
    /// view's `.task`; with `runsAutomatically` it then waits for the first screen to settle and runs.
    func start() async {
        guard phase == .preparing else { return }
        ListHarnessURLProtocol.install()
        coverDecodesAtStart = CoverDecodeCounter.value
        // A result left by an earlier run must not pass for this one's.
        await ListHarnessResult.removeLast()
        // What the launch sequence does before the first screen, which a harness launched in
        // place of the app skips; doing it again changes nothing.
        await imageCache.configure(.standard(physicalMemory: ProcessInfo.processInfo.physicalMemory))
        applySettings()
        galleries = await ListHarnessGalleries.make(
            count: options.galleryCount, session: session, coverLatency: options.coverLatency
        )
        ListHarnessCells.begin(galleries.map(\.gid))
        phase = .ready
        if options.observedSeconds > 0 {
            await observe()
        } else if options.runsAutomatically {
            for index in 1...options.runs {
                if index > 1 {
                    await startOver()
                }
                if options.hasCoversReady {
                    await loadCovers()
                }
                try? await Task.sleep(for: .seconds(ListHarnessOptions.settleDelay))
                guard !Task.isCancelled else { return }
                await run()
                guard case .finished = phase else { break }
            }
        } else {
            return
        }
        if options.exitsWhenDone {
            // Lets the last signposts reach the recording before the process goes away.
            try? await Task.sleep(for: .milliseconds(500))
            exit(0)
        }
    }

    func run() async {
        guard phase != .running, phase != .preparing, phase != .observing else { return }
        phase = .running
        let awake = options.keepsCoresAwake ? ListHarnessAwake() : nil
        awake?.start()
        let measured = await scroller.run(speed: options.speed)
        awake?.stop()
        guard let measured else {
            phase = .failed("No scroll view with room to scroll was found in the slot.")
            return
        }
        let result = ListHarnessResult(
            slot: options.slot.rawValue, options: options, galleryCount: galleries.count, scroll: measured,
            footprint: MemoryFootprint.current(),
            coversServed: ListHarnessURLProtocol.servedCount.withLock { $0 } - coversServedAtStart,
            coversDecoded: CoverDecodeCounter.value - coverDecodesAtStart
        )
        phase = .finished(result)
        results.append(result)
        await ListHarnessResult.write(results)
    }

    /// Watches the list for `observedSeconds` while a hand scrolls it. Every stretch of
    /// movement becomes a result, written as it ends, so that a watch cut short keeps what it
    /// has.
    private func observe() async {
        phase = .observing
        let awake = options.keepsCoresAwake ? ListHarnessAwake() : nil
        awake?.start()
        let observer = ListHarnessObserver(scroller: scroller) { [weak self] stretch in
            guard let self else { return }
            results.append(ListHarnessResult(
                slot: options.slot.rawValue, options: options, galleryCount: galleries.count, stretch: stretch,
                footprint: MemoryFootprint.current()
            ))
            save()
        }
        self.observer = observer
        observer.begin()
        try? await Task.sleep(for: .seconds(options.observedSeconds))
        observer.end()
        self.observer = nil
        awake?.stop()
        save()
        await lastSave?.value
        phase = .ready
    }

    /// Writes the results so far, after whatever write is still on its way: two writes at once
    /// could leave the file half of each.
    private func save() {
        let results = results
        let previous = lastSave
        lastSave = Task {
            await previous?.value
            await ListHarnessResult.write(results)
        }
    }

    /// Brings every cover into memory, a few at a time, before a scroll that is not to wait
    /// for any (`-HarnessCoversReady`).
    private func loadCovers() async {
        let urls = galleries.compactMap(\.coverURL)
        await withTaskGroup(of: Void.self) { group in
            var next = urls.makeIterator()
            for _ in 0..<8 {
                guard let url = next.next() else { break }
                group.addTask { _ = await CoverLoads.shared.load(url) }
            }
            while await group.next() != nil {
                if let url = next.next() {
                    group.addTask { _ = await CoverLoads.shared.load(url) }
                }
            }
        }
    }

    /// Between two runs of a series: the next run starts as a launch does, with nothing in the
    /// image cache, covers under URLs never asked for, and the list built from its first row.
    private func startOver() async {
        phase = .preparing
        await HarnessImageCache.empty()
        session = Self.newSession()
        coverDecodesAtStart = CoverDecodeCounter.value
        coversServedAtStart = ListHarnessURLProtocol.servedCount.withLock { $0 }
        galleries = await ListHarnessGalleries.make(
            count: options.galleryCount, session: session, coverLatency: options.coverLatency
        )
        ListHarnessCells.begin(galleries.map(\.gid))
        listID += 1
        phase = .ready
    }

    private static func newSession() -> String {
        String(UUID().uuidString.prefix(8).lowercased())
    }

    func stop() {
        scroller.cancel()
        observer?.end()
    }

    private func applyOptions(from old: ListHarnessOptions) {
        if options.showsTags != old.showsTags || options.slot != old.slot || options.showsBar != old.showsBar {
            applySettings()
        }
    }

    /// Before the slot is built, so a list lays itself out once in the form measured.
    private func applySettings() {
        settings.showsTagsInList = options.showsTags
        settings.wallDensity = options.slot.wallDensity ?? .medium
        settings.ledgerShowsCovers = options.slot != .ledgerTitles
        // The bar's place: Wall's first screen is the Front Page, which the list stands for.
        if options.showsBar {
            settings.designStart = .wall
        }
    }
}

/// What one run measured. The JSON keys are what `measure.sh` reads.
nonisolated struct ListHarnessResult: Equatable, Sendable, Codable {
    var slot: String
    var galleries: Int
    var tags: Bool
    var dock: Bool
    var speed: Double
    var duration: Double
    var frames: Int
    var distance: Double
    var reachedEnd: Bool
    var frameDurationMs: Double
    /// A stretch of a hand's scrolling (`-HarnessObserve`), not a scripted run.
    var byHand: Bool
    /// `-HarnessCoresAwake` and `-HarnessCoversReady`: the state the figures were taken in.
    var coresAwake: Bool
    var coversReady: Bool
    var footprintMB: Double
    var peakFootprintMB: Double
    var coversServed: Int
    /// Covers decoded by `CoverImage` during the harness; 0 for slots that do not use it.
    var coversDecoded: Int
    /// The main thread's CPU time from the scroll's first movement to its last (waiting for a
    /// core is not in it), and the cells built meanwhile. CPU time at whatever speed the
    /// system ran the thread at: on slow cores the same work is several times as much, so
    /// this compares runs in the same state (`coresAwake`), not lists across states.
    var mainThreadCPUMs: Double
    var cellsCreated: Int
    /// Whether `cellsCreated` counts cell bodies (`ListHarnessCells`); for a list whose cells
    /// do not count themselves it is the covers served during the scroll, which undercounts.
    var cellsCounted: Bool
    /// Of `cellsCreated`, the body runs for a cell the list had built before; and the cells
    /// standing built beyond where the list had got to at the end (`ListHarnessCells.Tally`).
    /// A list that builds what it shows has neither.
    var cellsBuiltAgain: Int
    var cellsBuiltAhead: Int
    var cpuPerCellMs: Double

    init(
        slot: String, options: ListHarnessOptions, galleryCount: Int, scroll: ListHarnessScroller.Result,
        footprint: MemoryFootprint?, coversServed: Int, coversDecoded: Int
    ) {
        self.slot = slot
        galleries = galleryCount
        tags = options.showsTags
        dock = options.showsDock
        speed = options.speed
        duration = scroll.duration
        frames = scroll.frames
        distance = scroll.distance
        reachedEnd = scroll.reachedEnd
        frameDurationMs = scroll.frameDuration * 1_000
        byHand = false
        coresAwake = options.keepsCoresAwake
        coversReady = options.hasCoversReady
        footprintMB = footprint.map { Double($0.current) / 1_048_576 } ?? 0
        peakFootprintMB = footprint.map { Double($0.peak) / 1_048_576 } ?? 0
        self.coversServed = coversServed
        self.coversDecoded = coversDecoded
        mainThreadCPUMs = scroll.mainThreadCPU * 1_000
        cellsCounted = scroll.cellBodies > 0
        cellsCreated = cellsCounted ? scroll.cellBodies : scroll.coversServed
        cellsBuiltAgain = scroll.cellsAgain
        cellsBuiltAhead = scroll.cellsAhead
        cpuPerCellMs = cellsCreated > 0 ? mainThreadCPUMs / Double(cellsCreated) : 0
    }

    /// One stretch of a hand's scrolling.
    init(
        slot: String, options: ListHarnessOptions, galleryCount: Int, stretch: ListHarnessObserver.Stretch,
        footprint: MemoryFootprint?
    ) {
        self.slot = slot
        galleries = galleryCount
        tags = options.showsTags
        dock = options.showsDock
        speed = stretch.duration > 0 ? stretch.distance / stretch.duration : 0
        duration = stretch.duration
        frames = stretch.frames
        distance = stretch.distance
        reachedEnd = false
        frameDurationMs = stretch.frameDuration * 1_000
        byHand = true
        coresAwake = options.keepsCoresAwake
        coversReady = options.hasCoversReady
        footprintMB = footprint.map { Double($0.current) / 1_048_576 } ?? 0
        peakFootprintMB = footprint.map { Double($0.peak) / 1_048_576 } ?? 0
        coversServed = stretch.coversServed
        coversDecoded = 0
        mainThreadCPUMs = stretch.mainThreadCPU * 1_000
        cellsCounted = stretch.cellBodies > 0
        cellsCreated = cellsCounted ? stretch.cellBodies : stretch.coversServed
        cellsBuiltAgain = stretch.cellsAgain
        cellsBuiltAhead = stretch.cellsAhead
        cpuPerCellMs = cellsCreated > 0 ? mainThreadCPUMs / Double(cellsCreated) : 0
    }

    static var fileURL: URL {
        URL.cachesDirectory.appending(path: "ListHarness/result.json")
    }

    var summary: String {
        String(
            format: "%@%@%@: %.1f s, %.0f pt, %d frames, footprint %.0f MB (peak %.0f MB), covers served %d, decoded by CoverImage %d, main thread %.0f ms for %d cells (%@; %d built before, %d built ahead), %.2f ms a cell%@",
            slot, dock ? " + dock" : "", byHand ? ", by hand" : "", duration, distance, frames, footprintMB, peakFootprintMB,
            coversServed, coversDecoded, mainThreadCPUMs, cellsCreated, cellsCounted ? "bodies" : "covers", cellsBuiltAgain,
            cellsBuiltAhead, cpuPerCellMs,
            coresAwake ? ", cores awake" : ""
        )
    }

    @concurrent
    static func removeLast() async {
        try? FileManager.default.removeItem(at: fileURL)
    }

    /// Writes the results of the launch so far off the main actor, one entry per run under
    /// `runs`, and prints the latest once, for `simctl launch --console`.
    @concurrent
    static func write(_ results: [ListHarnessResult]) async {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(ListHarnessResults(runs: results)) else { return }
        HarnessFile.write(data, to: Self.fileURL)
        if let latest = results.last {
            print("ListHarness result \(results.count): \(latest.summary)")
        }
    }
}

/// What `result.json` holds: every run of the launch, in order.
nonisolated struct ListHarnessResults: Codable, Sendable {
    var runs: [ListHarnessResult]
}

/// The process's memory footprint as the system counts it (what Xcode's gauge and jetsam use).
nonisolated struct MemoryFootprint: Equatable, Sendable {
    var current: UInt64
    var peak: UInt64

    static func current() -> MemoryFootprint? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard status == KERN_SUCCESS else { return nil }
        return MemoryFootprint(current: info.phys_footprint, peak: UInt64(max(info.ledger_phys_footprint_peak, 0)))
    }
}
#endif
