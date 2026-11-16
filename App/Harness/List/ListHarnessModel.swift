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
        case running
        case finished(ListHarnessResult)
        case failed(String)
    }

    var options: ListHarnessOptions {
        didSet { applyOptions(from: oldValue) }
    }
    private(set) var galleries: [Gallery] = []
    private(set) var phase = Phase.preparing

    /// The settings the list designs read, kept apart from the user's.
    @ObservationIgnored let settings: SettingsStore
    @ObservationIgnored let scroller = ListHarnessScroller()
    /// New cover URLs on every launch of the harness, so covers are downloaded and decoded.
    @ObservationIgnored private let session = UUID().uuidString.prefix(8).lowercased()
    /// `CoverDecodeCounter` when the harness started, so a run reports only its own decodes.
    @ObservationIgnored private var coverDecodesAtStart = 0
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
        phase = .ready
        guard options.runsAutomatically else { return }
        try? await Task.sleep(for: .seconds(ListHarnessOptions.settleDelay))
        guard !Task.isCancelled else { return }
        await run()
    }

    func run() async {
        guard phase != .running, phase != .preparing else { return }
        phase = .running
        guard let measured = await scroller.run(speed: options.speed) else {
            phase = .failed("No scroll view with room to scroll was found in the slot.")
            return
        }
        let result = ListHarnessResult(
            options: options, galleryCount: galleries.count, scroll: measured,
            footprint: MemoryFootprint.current(), coversServed: ListHarnessURLProtocol.servedCount.withLock { $0 },
            coversDecoded: CoverDecodeCounter.value - coverDecodesAtStart
        )
        phase = .finished(result)
        await result.write()
        if options.exitsWhenDone {
            // Lets the last signposts reach the recording before the process goes away.
            try? await Task.sleep(for: .milliseconds(500))
            exit(0)
        }
    }

    func stop() {
        scroller.cancel()
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
    var hitches: Int
    var hitchTimeMs: Double
    var hitchRatioMsPerS: Double
    var worstHitchMs: Double
    var longHitchesAfterFirstScreen: Int
    var footprintMB: Double
    var peakFootprintMB: Double
    var coversServed: Int
    /// Covers decoded by `CoverImage` during the harness; 0 for slots that do not use it.
    var coversDecoded: Int
    /// The main thread's CPU time from the scroll's first movement to its last (waiting for a
    /// core is not in it), and the cells built meanwhile: what `spikes/S1.md` compares lists
    /// by on a shared machine, where frame timing compares machine loads.
    var mainThreadCPUMs: Double
    var cellsCreated: Int
    /// Whether `cellsCreated` counts cell bodies (`ListHarnessCells`); for a list whose cells
    /// do not count themselves it is the covers served during the scroll, which undercounts.
    var cellsCounted: Bool
    var cpuPerCellMs: Double

    init(
        options: ListHarnessOptions, galleryCount: Int, scroll: ListHarnessScroller.Result,
        footprint: MemoryFootprint?, coversServed: Int, coversDecoded: Int
    ) {
        slot = options.slot.rawValue
        galleries = galleryCount
        tags = options.showsTags
        dock = options.showsDock
        speed = options.speed
        duration = scroll.duration
        frames = scroll.frames
        distance = scroll.distance
        reachedEnd = scroll.reachedEnd
        frameDurationMs = scroll.frameDuration * 1_000
        hitches = scroll.hitches
        hitchTimeMs = scroll.hitchTime * 1_000
        hitchRatioMsPerS = scroll.hitchRatio
        worstHitchMs = scroll.worstHitch * 1_000
        longHitchesAfterFirstScreen = scroll.longHitches
        footprintMB = footprint.map { Double($0.current) / 1_048_576 } ?? 0
        peakFootprintMB = footprint.map { Double($0.peak) / 1_048_576 } ?? 0
        self.coversServed = coversServed
        self.coversDecoded = coversDecoded
        mainThreadCPUMs = scroll.mainThreadCPU * 1_000
        cellsCounted = scroll.cellBodies > 0
        cellsCreated = cellsCounted ? scroll.cellBodies : scroll.coversServed
        cpuPerCellMs = cellsCreated > 0 ? mainThreadCPUMs / Double(cellsCreated) : 0
    }

    static var fileURL: URL {
        URL.cachesDirectory.appending(path: "ListHarness/result.json")
    }

    var summary: String {
        String(
            format: "%@%@: %.1f s, %d frames, hitch ratio %.1f ms/s, worst %.0f ms, %d long after the first screen, footprint %.0f MB (peak %.0f MB), covers served %d, decoded by CoverImage %d, main thread %.0f ms for %d cells (%@), %.2f ms a cell",
            slot, dock ? " + dock" : "", duration, frames, hitchRatioMsPerS, worstHitchMs, longHitchesAfterFirstScreen, footprintMB, peakFootprintMB,
            coversServed, coversDecoded, mainThreadCPUMs, cellsCreated, cellsCounted ? "bodies" : "covers", cpuPerCellMs
        )
    }

    @concurrent
    static func removeLast() async {
        try? FileManager.default.removeItem(at: fileURL)
    }

    /// Writes the result off the main actor and prints it once, for `simctl launch --console`.
    @concurrent
    func write() async {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(self) else { return }
        let url = Self.fileURL
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
        print("ListHarness result: \(summary)")
    }
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
