#if DEBUG || HARNESS
import Foundation

/// The calls of one scripted run of the reader harness, one per line, in the order they were
/// made:
///
/// - `D`: what the engine asked its data source (`pageCount`, `pageState`, `aspect`,
///   `hasTrailer`, `makeTrailer`);
/// - `E`: what it told its delegate (`page`, `needs`, `release`, `loaded` with the decoded
///   size, `failed`, `retry`, `panel`, `trailer`);
/// - `T`: what it handed its own prefetcher on every tiling change (`prefetch`, the visible
///   and the loaded pages) and every page view it filled (`configure` with the decode size,
///   `content` before a page view's `pageState` call);
/// - `M`: the script's marks, one at the end of each step.
///
/// Two records of the same script are compared by `ReaderHarnessComparison`.
final class ReaderHarnessRecorder {
    private(set) var lines: [String] = []

    func add(_ line: String) {
        lines.append(line)
    }

    func write(tag: String) {
        ReaderHarnessLog.write(lines.joined(separator: "\n") + "\n", to: "record-\(tag).txt")
    }
}

/// The files of the scripted runs, in `Library/Caches/ReaderHarness` in the app's container:
/// the records, the comparisons, `summary.txt` and `run.log` (one line per step that matters,
/// also printed, so a script on the host can wait for a line). Written in order on a queue of
/// their own, off the main thread.
nonisolated enum ReaderHarnessLog {
    private static let queue = DispatchQueue(label: "ReaderHarnessLog")

    static var directory: URL {
        URL.cachesDirectory.appending(path: "ReaderHarness")
    }

    static func write(_ text: String, to name: String) {
        queue.async {
            let directory = directory
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try? text.write(to: directory.appending(path: name), atomically: true, encoding: .utf8)
        }
    }

    static func removeAll() {
        queue.async {
            try? FileManager.default.removeItem(at: directory)
        }
    }

    static func line(_ text: String) {
        print("ReaderHarness: \(text)")
        queue.async {
            let directory = directory
            let url = directory.appending(path: "run.log")
            guard let data = (text + "\n").data(using: .utf8) else { return }
            if let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            } else {
                try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try? data.write(to: url)
            }
        }
    }
}
#endif
