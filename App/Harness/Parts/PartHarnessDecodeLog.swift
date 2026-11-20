#if DEBUG || HARNESS
import Foundation

/// The covers decoded and served since launch, written to `Documents/harness-decodes.txt` for
/// a script to read: a line whenever either count changed, checked once a second, as
/// `<seconds since launch> decoded <n> served <m>`. `decoded` is `CoverDecodeCounter` (one per
/// bitmap `CoverProcessor` made), `served` the covers the cover server answered (a download
/// that came from the disk cache is not served again). Runs in every launch of the part
/// harness as the whole app, until the harness goes.
enum PartHarnessDecodeLog {
    nonisolated static var fileURL: URL {
        URL.documentsDirectory.appending(path: "harness-decodes.txt")
    }

    static func run() async {
        let start = ContinuousClock.now
        var last: (decoded: Int, served: Int)?
        await write("", replacing: true)
        while !Task.isCancelled {
            let now = (decoded: CoverDecodeCounter.value, served: ListHarnessURLProtocol.servedCount.withLock { $0 })
            if last.map({ $0 != now }) ?? true {
                last = now
                let seconds = (ContinuousClock.now - start).components.seconds
                await write("\(seconds) decoded \(now.decoded) served \(now.served)\n", replacing: false)
            }
            try? await Task.sleep(for: .seconds(1))
        }
    }

    @concurrent
    nonisolated private static func write(_ text: String, replacing: Bool) async {
        let data = Data(text.utf8)
        guard !replacing, let handle = try? FileHandle(forWritingTo: fileURL) else {
            try? data.write(to: fileURL, options: .atomic)
            return
        }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: data)
    }
}
#endif
