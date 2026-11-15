import Foundation
import Synchronization

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
}

/// Lets a download's progress through a few times a second: the first report, then one per
/// `interval`, and the last, when every byte is in. A page's ring and text follow at that
/// pace, which is all they need, and the main actor hears of each download that often instead
/// of once per piece of data.
///
/// Kingfisher calls the progress block on the main queue; the lock keeps it right on any.
nonisolated final class ImageLoadProgressThrottle: Sendable {
    static let interval: Duration = .milliseconds(250)

    private let lastAdmitted = Mutex<ContinuousClock.Instant?>(nil)

    func admits(received: Int64, expected: Int64, now: ContinuousClock.Instant = .now) -> Bool {
        lastAdmitted.withLock { last in
            let isComplete = received >= expected
            if let previous = last, !isComplete, now - previous < Self.interval {
                return false
            }
            last = now
            return true
        }
    }
}
