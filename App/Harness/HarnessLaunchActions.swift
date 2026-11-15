import SwiftUI
#if DEBUG || HARNESS
import Kingfisher
#endif

extension View {
    /// What a measuring run asks of the real app at launch, read from its launch arguments, in
    /// builds with the harness; elsewhere nothing. `Scripts/measure.sh signposts`
    /// passes them, so a gallery or the reader can be measured on a phone nobody taps:
    ///
    /// | Argument | Meaning |
    /// |---|---|
    /// | `-HarnessLink <url>` | Opens the link once, as a link from outside would be opened: a gallery link opens the gallery sheet, a link to an image page also opens the reader at that page. |
    /// | `-HarnessClearImageCache YES` | Empties the image cache, memory and disk, before the link is opened, so the cover and the pages download again. |
    /// | `-HarnessExitAfter <s>` | That many seconds after the root appears, writes the memory footprint to `Library/Caches/ListHarness/footprint.json` and quits, which ends the recording. |
    ///
    /// A launch argument and not an `ehshoko://` link: a phone with two builds of the app may
    /// hand the link to the other one.
    @ViewBuilder
    func harnessLaunchActions(open: @escaping (URL) -> Void) -> some View {
        #if DEBUG || HARNESS
        modifier(HarnessLaunchActions(open: open))
        #else
        self
        #endif
    }
}

#if DEBUG || HARNESS
private struct HarnessLaunchActions: ViewModifier {
    let open: (URL) -> Void

    /// The actions run once per process even if the root's task restarts.
    private static var hasRun = false

    func body(content: Content) -> some View {
        content.task {
            guard !Self.hasRun, let request = HarnessLaunchRequest.atLaunch else { return }
            Self.hasRun = true
            await request.perform(open: open)
        }
    }
}

nonisolated struct HarnessLaunchRequest: Sendable {
    var link: URL?
    var clearsImageCache = false
    var exitAfter: Double?

    /// The request of the launch arguments, or `nil` when they ask for nothing.
    static var atLaunch: HarnessLaunchRequest? {
        let defaults = UserDefaults.standard
        var request = HarnessLaunchRequest()
        request.link = defaults.string(forKey: "HarnessLink").flatMap(URL.init(string:))
        request.clearsImageCache = defaults.bool(forKey: "HarnessClearImageCache")
        let exitAfter = defaults.double(forKey: "HarnessExitAfter")
        request.exitAfter = exitAfter > 0 ? exitAfter : nil
        let asksForNothing = request.link == nil && !request.clearsImageCache && request.exitAfter == nil
        return asksForNothing ? nil : request
    }

    @MainActor
    func perform(open: (URL) -> Void) async {
        // A footprint left by an earlier run must not pass for this one's.
        await HarnessFootprint.removeLast()
        if clearsImageCache {
            ImagePipeline.cache.clearMemoryCache()
            await withCheckedContinuation { continuation in
                ImagePipeline.cache.clearDiskCache { continuation.resume() }
            }
        }
        if let link {
            open(link)
        }
        guard let exitAfter else { return }
        do {
            try await Task.sleep(for: .seconds(exitAfter))
        } catch {
            return
        }
        await HarnessFootprint(MemoryFootprint.current()).write()
        exit(0)
    }
}

/// The footprint a timed run ends with; the JSON keys are what `measure.sh` reads.
nonisolated struct HarnessFootprint: Codable, Sendable {
    var footprintMB: Double
    var peakFootprintMB: Double

    init(_ footprint: MemoryFootprint?) {
        footprintMB = footprint.map { Double($0.current) / 1_048_576 } ?? 0
        peakFootprintMB = footprint.map { Double($0.peak) / 1_048_576 } ?? 0
    }

    static var fileURL: URL {
        URL.cachesDirectory.appending(path: "ListHarness/footprint.json")
    }

    @concurrent
    static func removeLast() async {
        try? FileManager.default.removeItem(at: fileURL)
    }

    @concurrent
    func write() async {
        guard let data = try? JSONEncoder().encode(self) else { return }
        let url = Self.fileURL
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}
#endif
