#if DEBUG || HARNESS
import EhFeatures
import Foundation
import UIKit

/// What one keystroke costs on the main thread, measured as spike S6 did (section 9): from
/// the moment the key is sent, through the field, the model and the views that read it, to
/// the end of that run-loop turn, after SwiftUI's update and Core Animation's commit.
///
/// `-HarnessSearchType "<text>"` types `text` into whatever has focus, one character every
/// `-HarnessSearchTypeGap` ms (120), after `-HarnessSearchTypeDelay` s (4); the field is
/// focused first. `-HarnessSearchScript "type:-gla|wait:1500|accept:0|key:artist:|use:…"`
/// runs steps instead: typing, a pause, taking suggestion n, a key at the caret, a keyword
/// handed in, putting the keyboard away (`blur:`). The summary goes to `Documents/search-keystrokes.txt`. Keys are sent through
/// `UIKeyInput.insertText` on the first responder, as the keyboard does, so the same script
/// types into today's `.searchable` field for a comparison.
@MainActor
final class SearchKeystrokeProbe {
    private var started: UInt64?
    private var samples: [Double] = []
    private var observer: CFRunLoopObserver?
    private static var hasRun = false

    /// Runs once per launch, in a task of its own: the surface's own tasks end whenever it
    /// leaves the screen. `describe` says what the model holds at the end.
    static func runIfRequested(
        field: TagSearchFieldController, model: SearchSurfaceModel, describe: @escaping () -> String
    ) {
        let defaults = UserDefaults.standard
        let typed = defaults.string(forKey: "HarnessSearchType").map { "type:" + $0 }
        guard !hasRun, let script = defaults.string(forKey: "HarnessSearchScript") ?? typed, !script.isEmpty
        else { return }
        hasRun = true
        let gap = defaults.integer(forKey: "HarnessSearchTypeGap") > 0 ? defaults.integer(forKey: "HarnessSearchTypeGap") : 120
        let delay = defaults.integer(forKey: "HarnessSearchTypeDelay") > 0 ? defaults.integer(forKey: "HarnessSearchTypeDelay") : 4
        Task {
            try? await Task.sleep(for: .seconds(delay))
            field.focus()
            try? await Task.sleep(for: .seconds(1))
            // Today's screen (the design adapters) has a `.searchable` field the controller
            // does not know: focus the first search field on screen instead.
            if FirstResponder.current == nil { focusFirstSearchField() }
            try? await Task.sleep(for: .seconds(1))
            let probe = SearchKeystrokeProbe()
            probe.install()
            for step in script.split(separator: "|") {
                await probe.run(String(step), field: field, model: model, gap: gap)
            }
            try? await Task.sleep(for: .seconds(1))
            probe.finish(text: script, gap: gap, state: describe())
        }
    }

    private func run(_ step: String, field: TagSearchFieldController, model: SearchSurfaceModel, gap: Int) async {
        guard let colon = step.firstIndex(of: ":") else { return }
        let argument = String(step[step.index(after: colon)...])
        switch step[..<colon] {
        case "type":
            for character in argument {
                begin()
                FirstResponder.current?.insertText(String(character))
                try? await Task.sleep(for: .milliseconds(gap))
            }
        case "wait":
            try? await Task.sleep(for: .milliseconds(Int(argument) ?? 1000))
        case "accept":
            let suggestions = model.suggestions.suggestions
            if let index = Int(argument), suggestions.indices.contains(index) { field.accept(suggestions[index]) }
        case "key":
            field.insert(argument)
        case "use":
            field.use(argument)
        case "blur":
            field.blur()
        default:
            break
        }
    }

    private static func focusFirstSearchField() {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
        func find(in view: UIView) -> UISearchTextField? {
            if let field = view as? UISearchTextField, field.window != nil, !field.isHidden { return field }
            for subview in view.subviews {
                if let field = find(in: subview) { return field }
            }
            return nil
        }
        for window in windows where window.isKeyWindow {
            _ = find(in: window)?.becomeFirstResponder()
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

    private func finish(text: String, gap: Int, state: String) {
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
        let line = Data((summary + "state " + state + "\nsamples " + samples.map { String(format: "%.1f", $0) }.joined(separator: " ") + "\n").utf8)
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
