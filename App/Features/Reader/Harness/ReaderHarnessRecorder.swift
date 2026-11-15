#if DEBUG || HARNESS
import EhFeatures
import Foundation
import QuartzCore

/// The calls of one reader of the harness, one per line, in the order they were made:
///
/// - `D` what the engine asked its data source,
/// - `E` what it told its delegate,
/// - `T` what it decided by itself (`ReaderEngineProbeEvent`),
/// - `M` the marks of the script that drove it.
///
/// Two records of the same script are compared by `ReaderHarnessComparison`.
final class ReaderHarnessRecorder {
    private(set) var lines: [String] = []

    func add(_ line: String) {
        lines.append(line)
    }

    func add(_ event: ReaderEngineProbeEvent) {
        switch event {
        case .prefetch(let visible, let loaded):
            add("T prefetch visible=\(Self.text(visible)) loaded=\(Self.text(loaded))")
        case .configure(let page, let request):
            let target = request.target
            add("T configure \(page) px=\(target.pixelWidth)x\(target.pixelHeight ?? 0) keeps=\(request.keepsInMemory)")
        case .pageContent(let page):
            add("T content \(page)")
        }
    }

    private static func text(_ range: ClosedRange<Int>?) -> String {
        range.map { "\($0.lowerBound)...\($0.upperBound)" } ?? "none"
    }
}

/// Where the reader harness writes what its checks find: `Library/Caches/ReaderHarness/` in
/// the app's container, which a script on the Mac reads. Writing happens off the main thread.
nonisolated enum ReaderHarnessFiles {
    static let directory = URL.cachesDirectory.appending(path: "ReaderHarness", directoryHint: .isDirectory)

    private static let queue = DispatchQueue(label: "app.ehshoko.reader-harness.files", qos: .utility)
    private static let origin = CACurrentMediaTime()

    /// Replaces a file.
    static func write(_ lines: [String], to name: String) {
        let text = lines.joined(separator: "\n") + "\n"
        queue.async {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try? text.write(to: directory.appending(path: name), atomically: true, encoding: .utf8)
        }
    }

    /// Adds lines to the end of a file.
    static func append(_ lines: [String], to name: String) {
        let data = Data((lines.joined(separator: "\n") + "\n").utf8)
        queue.async {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appending(path: name)
            if let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            } else {
                try? data.write(to: url)
            }
        }
    }

    static func remove(_ name: String) {
        queue.async {
            try? FileManager.default.removeItem(at: directory.appending(path: name))
        }
    }

    /// A line of `log.txt`, stamped with the seconds since the harness first wrote.
    static func log(_ line: String) {
        append([String(format: "%9.3f ", CACurrentMediaTime() - origin) + line], to: "log.txt")
    }
}

/// Counts the frames the main thread delivered late between `start()` and `stop()`. It shows
/// main-thread stalls, not what the render server did.
final class ReaderHarnessFrameMeter: NSObject {
    struct Result {
        var frames = 0
        var late = 0
        var worst = 0.0

        var text: String {
            String(format: "frames=%d late=%d worst=%.0fms", frames, late, worst * 1_000)
        }
    }

    private var link: CADisplayLink?
    private var previous: CFTimeInterval = 0
    private var result = Result()

    func start() {
        link?.invalidate()
        result = Result()
        previous = 0
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func stop() -> Result {
        link?.invalidate()
        link = nil
        return result
    }

    @objc private func tick(_ link: CADisplayLink) {
        defer { previous = link.timestamp }
        guard previous > 0 else { return }
        let interval = link.timestamp - previous
        result.frames += 1
        result.worst = max(result.worst, interval)
        if interval > link.duration * 1.5 {
            result.late += 1
        }
    }
}
#endif
