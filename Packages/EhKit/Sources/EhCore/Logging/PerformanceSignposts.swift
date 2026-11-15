import Foundation
import os

/// The timings the performance budgets are measured with (`Design/designs/README.md` 9.5).
///
/// Each is an `os_signpost` interval under subsystem `app.ehshoko`, category `Performance`,
/// which Instruments shows in its os_signpost and Points of Interest tracks and
/// `Scripts/measure.sh signposts` prints. A signpost is not a log line: it costs a
/// few nanoseconds when nothing records it, so it may mark every page load and every screen.
///
/// | Interval | From | To |
/// |---|---|---|
/// | `Launch` | `MainApp.init` | the root view's first appearance |
/// | `FirstContent` | `MainApp.init` | the first screen's rows are in its model (event `LaunchReady` in between) |
/// | `GalleryOpen` | the gallery page's first load | its fetched page is applied (event `Stored` when the database's copy is) |
/// | `ReaderOpen` | the reader starts | its first page is shown |
/// | `ListPage` | a list page is requested | its galleries are applied |
public enum PerformanceSignposts {
    public static let subsystem = AppLogger.subsystem
    public static let category = "Performance"

    static let signposter = OSSignposter(subsystem: subsystem, category: category)

    public enum Name: String, Sendable, CaseIterable {
        case launch = "Launch"
        case firstContent = "FirstContent"
        case galleryOpen = "GalleryOpen"
        case readerOpen = "ReaderOpen"
        case listPage = "ListPage"

        /// `OSSignposter` takes names as static strings only.
        var staticName: StaticString {
            switch self {
            case .launch: "Launch"
            case .firstContent: "FirstContent"
            case .galleryOpen: "GalleryOpen"
            case .readerOpen: "ReaderOpen"
            case .listPage: "ListPage"
            }
        }
    }

    /// Begins an interval. `detail` says which one it is (a list's source, "first" or "next");
    /// never put a title or anything else the user would not want recorded in it.
    public static func begin(_ name: Name, _ detail: String = "") -> PerformanceInterval {
        PerformanceInterval(name: name, detail: detail, signposter: signposter)
    }

    // MARK: Launch

    /// The once-per-process `Launch` and `FirstContent` intervals.
    static let launch = LaunchSignposts(signposter: signposter)

    /// Call first thing in the app's `init`. Begins `Launch` and `FirstContent`.
    public static func appStarted() {
        launch.start()
    }

    /// Call when the root view first appears. Ends `Launch`, noting the time since the process
    /// started, which includes what ran before `main`.
    public static func rootAppeared() {
        launch.rootAppeared()
    }

    /// The launch sequence is done and the first screen is about to be built: an event inside
    /// `FirstContent`, so the time spent waiting for the network shows separately.
    public static func launchReady() {
        launch.ready()
    }

    /// Call where a screen's first rows are applied. Only the first call in the process ends
    /// `FirstContent`; every later one does nothing.
    public static func contentShown(_ detail: String) {
        launch.contentShown(detail)
    }
}

/// One interval in progress. Ending it more than once does nothing, and one released without
/// being ended (its owner went away first) ends as "abandoned", so no interval stays open in a
/// recording.
public final class PerformanceInterval: Sendable {
    private let name: PerformanceSignposts.Name
    private let signposter: OSSignposter
    // `OSSignpostIntervalState` is not marked `Sendable`; it is only touched under this lock.
    private let state: OSAllocatedUnfairLock<OSSignpostIntervalState?>

    init(name: PerformanceSignposts.Name, detail: String, signposter: OSSignposter) {
        self.name = name
        self.signposter = signposter
        let id = signposter.makeSignpostID()
        let begun = signposter.beginInterval(name.staticName, id: id, "\(detail, privacy: .public)")
        state = OSAllocatedUnfairLock(uncheckedState: begun)
    }

    /// Whether the interval has ended.
    public var isEnded: Bool {
        state.withLockUnchecked { $0 == nil }
    }

    /// Marks a moment inside the interval, such as "the stored copy is on screen".
    public func event(_ message: String) {
        guard !isEnded else { return }
        signposter.emitEvent(name.staticName, "\(message, privacy: .public)")
    }

    /// Ends the interval with what happened ("done", "failed", "cancelled", "24 rows").
    public func end(_ outcome: String = "done") {
        let begun = state.withLockUnchecked { state -> OSSignpostIntervalState? in
            defer { state = nil }
            return state
        }
        guard let begun else { return }
        signposter.endInterval(name.staticName, begun, "\(outcome, privacy: .public)")
    }

    deinit {
        end("abandoned")
    }
}

/// `Launch` and `FirstContent`: each begins once, at the start of the process, and ends once.
final class LaunchSignposts: Sendable {
    private struct Intervals {
        var hasStarted = false
        var launch: PerformanceInterval?
        var firstContent: PerformanceInterval?
    }

    private let signposter: OSSignposter
    private let intervals = OSAllocatedUnfairLock(initialState: Intervals())

    init(signposter: OSSignposter) {
        self.signposter = signposter
    }

    /// Begins both intervals, once per instance.
    func start() {
        intervals.withLock { intervals in
            guard !intervals.hasStarted else { return }
            intervals.hasStarted = true
            intervals.launch = PerformanceInterval(name: .launch, detail: "", signposter: signposter)
            intervals.firstContent = PerformanceInterval(name: .firstContent, detail: "", signposter: signposter)
        }
    }

    /// Ends `Launch`. Returns whether this call ended it.
    @discardableResult
    func rootAppeared() -> Bool {
        guard let launch = take(\.launch) else { return false }
        let milliseconds = ProcessStart.millisecondsSinceStart().map { "\($0) ms since process start" } ?? "done"
        launch.end(milliseconds)
        return true
    }

    func ready() {
        intervals.withLock { $0.firstContent }?.event("LaunchReady")
    }

    /// Ends `FirstContent`. Returns whether this call ended it.
    @discardableResult
    func contentShown(_ detail: String) -> Bool {
        guard let firstContent = take(\.firstContent) else { return false }
        firstContent.end(detail)
        return true
    }

    /// Hands the interval over once, leaving `nil` behind. Ending it outside the lock keeps
    /// the signpost call out of the critical section.
    private func take(_ keyPath: WritableKeyPath<Intervals, PerformanceInterval?> & Sendable) -> PerformanceInterval? {
        intervals.withLock { intervals in
            defer { intervals[keyPath: keyPath] = nil }
            return intervals[keyPath: keyPath]
        }
    }
}

/// When the process started, from the kernel, so the launch timing includes the time before
/// `main` that no code of the app can mark.
enum ProcessStart {
    static func millisecondsSinceStart(now: Date = Date()) -> Int? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var name: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&name, u_int(name.count), &info, &size, nil, 0) == 0 else { return nil }
        let start = info.kp_proc.p_un.__p_starttime
        let started = Date(timeIntervalSince1970: TimeInterval(start.tv_sec) + TimeInterval(start.tv_usec) / 1_000_000)
        return Int((now.timeIntervalSince(started) * 1_000).rounded())
    }
}
