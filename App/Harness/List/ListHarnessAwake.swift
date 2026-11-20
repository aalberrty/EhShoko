#if DEBUG || HARNESS
import Foundation
import os

/// Keeps the performance cores at their top speed while a list scrolls (`-HarnessCoresAwake
/// YES`): one thread at the highest priority that does nothing as fast as it can.
///
/// A scripted scroll leaves the main thread idle for most frames, and the system answers by
/// running it slowly: on the efficiency cores on a phone, at the lowest frequency on an iPad.
/// The burst of work when a row comes in then takes several times as long as the same work
/// at speed, and that, not the row, decides the hitch ratio. With this thread running the
/// main thread stays on fast cores, so a figure taken with it says what the list costs, and
/// one taken without it says what the system made of it. It exists only in builds with the
/// harness, and only while a harness run asks for it.
nonisolated final class ListHarnessAwake: Sendable {
    private let isStopped = OSAllocatedUnfairLock(initialState: false)

    func start() {
        let thread = Thread { [isStopped] in
            var value: UInt64 = 1
            while !isStopped.withLock({ $0 }) {
                for _ in 0..<20_000 {
                    value = value &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                }
            }
            // Read once, so the loop is not optimised away.
            if value == 0 { Thread.sleep(forTimeInterval: 0) }
        }
        thread.name = "ListHarnessAwake"
        thread.qualityOfService = .userInteractive
        thread.start()
    }

    func stop() {
        isStopped.withLock { $0 = true }
    }
}
#endif
