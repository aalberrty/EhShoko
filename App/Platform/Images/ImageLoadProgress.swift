import Foundation

/// How far a download has come: the bytes received and the bytes the server said it would
/// send. A page's status view shows both ("Loading · 1.4 MB of 2.3 MB") and the fraction.
nonisolated struct ImageLoadProgress: Equatable, Sendable {
    var receivedBytes: Int64
    /// Always above 0: a download whose size is unknown reports no progress.
    var expectedBytes: Int64

    /// From 0 to 1.
    var fraction: Double {
        guard expectedBytes > 0 else { return 0 }
        return min(max(Double(receivedBytes) / Double(expectedBytes), 0), 1)
    }

    var isComplete: Bool { receivedBytes >= expectedBytes }
}

/// Lets a page's progress through a few times a second: the first report, then one per
/// `interval`, and the last, when every byte is in. Downloads report once per piece of data,
/// dozens of times a second on a fast connection, and a page can start its load again while
/// its decode size settles; one gate per page keeps what it shows at this pace through both.
nonisolated struct ImageLoadProgressGate {
    static let interval: Duration = .milliseconds(250)

    private var lastAdmitted: ContinuousClock.Instant?

    mutating func admits(_ progress: ImageLoadProgress, now: ContinuousClock.Instant = .now) -> Bool {
        if let lastAdmitted, !progress.isComplete, now - lastAdmitted < Self.interval {
            return false
        }
        lastAdmitted = now
        return true
    }
}
