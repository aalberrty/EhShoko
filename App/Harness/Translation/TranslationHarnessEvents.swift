#if DEBUG || HARNESS
import EhCore
import Foundation

/// A session's events as the run waits for them: the first final status of each page, and
/// a wait for one page's that ends at a deadline.
actor TranslationHarnessEvents {
    struct Final: Sendable {
        var event: PageTranslationEvent
        var at: ContinuousClock.Instant
    }

    private var finals: [Int: Final] = [:]
    private var waiters: [Int: CheckedContinuation<Final?, Never>] = [:]
    private var listening: Task<Void, Never>?

    /// Reads `events` until they end.
    func listen(to events: AsyncStream<PageTranslationEvent>) {
        listening = Task { [weak self] in
            for await event in events {
                await self?.deliver(event)
            }
        }
    }

    func stop() {
        listening?.cancel()
        for waiter in waiters.values { waiter.resume(returning: nil) }
        waiters = [:]
    }

    func final(of index: Int) -> Final? { finals[index] }

    /// The page's first final status, or `nil` when `deadline` comes first.
    func waitForFinal(of index: Int, until deadline: ContinuousClock.Instant) async -> Final? {
        if let final = finals[index] { return final }
        let timeout = Task { [weak self] in
            try? await Task.sleep(until: deadline)
            await self?.timeOut(index)
        }
        defer { timeout.cancel() }
        return await withCheckedContinuation { continuation in
            waiters[index] = continuation
        }
    }

    private func deliver(_ event: PageTranslationEvent) {
        guard event.status.isFinal else { return }
        // A page that comes back into the window is reported again; the first report is the
        // one with its work in it.
        if let earlier = finals[event.pageIndex], earlier.event.report != nil || event.report == nil { return }
        let final = Final(event: event, at: .now)
        finals[event.pageIndex] = final
        waiters.removeValue(forKey: event.pageIndex)?.resume(returning: final)
    }

    private func timeOut(_ index: Int) {
        waiters.removeValue(forKey: index)?.resume(returning: nil)
    }
}
#endif
