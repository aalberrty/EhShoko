import Foundation

/// In-memory defaults that count the writes to each key, so a test can say how often a
/// store wrote a preference (once per change, never on a read).
///
/// `@unchecked Sendable` as `UserDefaults` itself: the dictionaries are only touched under
/// `lock`.
public final class CountingDefaults: UserDefaults, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Any] = [:]
    private var writes: [String: Int] = [:]

    public init() {
        // A suite of no name is the app's own domain: the overrides below keep everything in
        // memory, so nothing is read from or written to it.
        super.init(suiteName: nil)!
    }

    override public func object(forKey key: String) -> Any? {
        lock.withLock { values[key] }
    }

    override public func set(_ value: Any?, forKey key: String) {
        lock.withLock {
            values[key] = value
            writes[key, default: 0] += 1
        }
    }

    override public func removeObject(forKey key: String) {
        lock.withLock {
            values[key] = nil
            writes[key, default: 0] += 1
        }
    }

    /// Forgets the writes counted so far; the values stay.
    public func reset() {
        lock.withLock { writes.removeAll() }
    }

    /// The writes to each key that was written, set or removed, since the last `reset()`.
    public var writesByKey: [String: Int] {
        lock.withLock { writes }
    }

    /// Every write since the last `reset()`.
    public var total: Int {
        lock.withLock { writes.values.reduce(0, +) }
    }
}
