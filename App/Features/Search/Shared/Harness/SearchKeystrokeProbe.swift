#if DEBUG || HARNESS
import Foundation
import UIKit

/// What one keystroke costs on the main thread, measured as spike S6 did (section 9): from
/// the moment the key is sent, through the field, the model and the views that read it, to
/// the end of that run-loop turn, after SwiftUI's update and Core Animation's commit.
///
/// `-HarnessSearchType "<text>"` types `text` into whatever has focus, one character every
/// `-HarnessSearchTypeGap` ms (120), after `-HarnessSearchTypeDelay` s (4); the field is
/// focused first. The summary goes to `Documents/search-keystrokes.txt`. The keys are sent
/// through `UIKeyInput.insertText` on the first responder, as the keyboard does, so the same
/// script types into today's `.searchable` field for a comparison.
@MainActor
final class SearchKeystrokeProbe {
    private var started: UInt64?
    private var samples: [Double] = []
    private var observer: CFRunLoopObserver?

    static func runIfRequested(field: TagSearchFieldController?) async {
        let defaults = UserDefaults.standard
        guard let text = defaults.string(forKey: "HarnessSearchType"), !text.isEmpty else { return }
        let gap = defaults.object(forKey: "HarnessSearchTypeGap") as? Int ?? 120
        let delay = defaults.object(forKey: "HarnessSearchTypeDelay") as? Int ?? 4
        do {
            try await Task.sleep(for: .seconds(delay))
            field?.focus()
            try await Task.sleep(for: .seconds(1))
            let probe = SearchKeystrokeProbe()
            probe.install()
            for character in text {
                probe.begin()
                FirstResponder.current?.insertText(String(character))
                try await Task.sleep(for: .milliseconds(gap))
            }
            probe.finish(text: text, gap: gap)
        } catch {
            return
        }
    }

    private func install() {
        // Ordered last, so the turn's SwiftUI update and commit come before it.
        let observer = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.beforeWaiting.rawValue, true, CFIndex.max) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.end() }
        }
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
        self.observer = observer
    }

    private func begin() {
        started = DispatchTime.now().uptimeNanoseconds
    }

    private func end() {
        guard let started else { return }
        self.started = nil
        samples.append(Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000)
    }

    private func finish(text: String, gap: Int) {
        if let observer { CFRunLoopRemoveObserver(CFRunLoopGetMain(), observer, .commonModes) }
        let sorted = samples.sorted()
        func percentile(_ p: Double) -> Double {
            sorted.isEmpty ? 0 : sorted[min(sorted.count - 1, Int(Double(sorted.count) * p))]
        }
        var load = [Double](repeating: 0, count: 3)
        getloadavg(&load, 3)
        let summary = String(
            format: "keystrokes %d gap %d ms median %.1f p90 %.1f max %.1f ms load %.0f %.0f %.0f field %@\n",
            sorted.count, gap, percentile(0.5), percentile(0.9), sorted.last ?? 0, load[0], load[1], load[2],
            String(describing: type(of: FirstResponder.current as Any))
        )
        guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let url = documents.appending(path: "search-keystrokes.txt")
        let line = Data((summary + "samples " + samples.map { String(format: "%.1f", $0) }.joined(separator: " ") + "\n").utf8)
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(line)
            try? handle.close()
        } else {
            try? line.write(to: url)
        }
    }
}

/// The first responder, found the way UIKit's own actions find their target.
@MainActor
private enum FirstResponder {
    private static weak var found: UIResponder?

    static var current: (UIResponder & UIKeyInput)? {
        found = nil
        UIApplication.shared.sendAction(#selector(UIResponder.searchProbeCapture), to: nil, from: nil, for: nil)
        return found as? UIResponder & UIKeyInput
    }

    fileprivate static func capture(_ responder: UIResponder) {
        found = responder
    }
}

extension UIResponder {
    @objc fileprivate func searchProbeCapture() {
        FirstResponder.capture(self)
    }
}
#endif
