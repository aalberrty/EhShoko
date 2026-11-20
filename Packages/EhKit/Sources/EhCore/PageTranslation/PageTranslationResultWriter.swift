import EhDatabase
import EhModels
import Foundation

/// Saves translated pages in batches, and reads them back including those not yet written.
///
/// Pages finish about a second apart, so results are collected for `delay` after the first of a
/// burst and written in one transaction. Every write goes through one queue, so a delete can
/// never be overtaken by an older save, and the queue's tasks finish after the reader that made
/// the results has closed. The service holds one writer for the process and calls `flush()`
/// when a reader closes.
///
/// Reads go through the writer rather than straight to the database: a result waiting for its
/// batch, or in a write that has not committed, is still found, so a page is never translated
/// twice because it came back into view within the delay.
public actor PageTranslationResultWriter {
    /// How long results are collected before they are written: longer than a page takes, so a
    /// run of pages shares a transaction; short enough that little is lost if the app is killed.
    public static let defaultDelay: Duration = .seconds(2)
    /// Stored pages of a gallery neither opened nor translated for this long are removed, by
    /// the database's expiry and by the patch store's.
    public static let retention: TimeInterval = 30 * 24 * 60 * 60

    private struct PageKey: Hashable {
        var gid: String
        var modelSetKey: String
        var pageIndex: Int

        init(_ translation: PageTranslation) {
            self.init(gid: translation.gid, modelSetKey: translation.modelSetKey, pageIndex: translation.pageIndex)
        }

        init(gid: String, modelSetKey: String, pageIndex: Int) {
            self.gid = gid
            self.modelSetKey = modelSetKey
            self.pageIndex = pageIndex
        }
    }

    private let database: AppDatabase
    private let logger: AppLogger
    private let clock: any Clock<Duration>
    private let delay: Duration

    /// Results waiting for the next batch.
    private var pending: [PageKey: PageTranslation] = [:]
    /// Results in a batch whose write has not finished.
    private var inFlight: [PageKey: PageTranslation] = [:]
    /// Deletes queued and not finished: reads wait for them, so nothing deleted is found again.
    private var queuedDeletes = 0
    private var timer: Task<Void, Never>?
    private var lastWrite: Task<Void, Never>?
    /// Database transactions started so far. Tests read it to see that results are batched.
    public private(set) var writeCount = 0

    public init(
        database: AppDatabase, logger: AppLogger,
        clock: any Clock<Duration> = ContinuousClock(), delay: Duration = defaultDelay
    ) {
        self.database = database
        self.logger = logger
        self.clock = clock
        self.delay = delay
    }

    // MARK: - Writing

    /// Queues a page's result for the next batch, replacing one queued for the same page.
    public func add(_ translation: PageTranslation) {
        pending[PageKey(translation)] = translation
        guard timer == nil else { return }
        // Timed from the first result of a burst, so a long run still writes regularly.
        timer = Task { [weak self, clock, delay] in
            do {
                try await clock.sleep(for: delay)
            } catch {
                return
            }
            await self?.flush()
        }
    }

    /// Writes every queued result now.
    public func flush() {
        timer?.cancel()
        timer = nil
        guard !pending.isEmpty else { return }
        let batch = pending
        pending = [:]
        inFlight.merge(batch) { _, newer in newer }
        let translations = batch.values.sorted { ($0.gid, $0.pageIndex) < ($1.gid, $1.pageIndex) }
        enqueue { [database] in
            try await database.savePageTranslations(translations)
        } completion: { writer in
            for (key, translation) in batch where writer.inFlight[key] == translation {
                writer.inFlight[key] = nil
            }
        }
    }

    /// Forgets a gallery's queued results and deletes its stored pages.
    public func deleteTranslations(gid: String) {
        pending = pending.filter { $0.key.gid != gid }
        inFlight = inFlight.filter { $0.key.gid != gid }
        enqueueDelete { database in try await database.deletePageTranslations(gid: gid) }
    }

    /// Forgets every queued result and deletes every stored page.
    public func deleteAllTranslations() {
        timer?.cancel()
        timer = nil
        pending = [:]
        inFlight = [:]
        enqueueDelete { database in try await database.deleteAllPageTranslations() }
    }

    /// Deletes stored pages of every model set but `modelSetKey`, and of galleries neither opened
    /// nor translated within `retention`. The service calls it the first time it is used in a
    /// process, never at launch.
    public func removeExpired(keepingModelSetKey modelSetKey: String, now: Date = .now) {
        flush()
        pending = [:]
        inFlight = inFlight.filter { $0.key.modelSetKey == modelSetKey }
        enqueueDelete { database in
            try await database.deleteExpiredPageTranslations(
                keepingModelSetKey: modelSetKey, notOpenedWithin: Self.retention, now: now
            )
        }
    }

    /// Returns when every write queued so far has finished.
    public func waitUntilWritten() async {
        while let write = lastWrite {
            await write.value
            if lastWrite == write { return }
        }
    }

    // MARK: - Reading

    /// A page's stored result for `modelSetKey`, including one not yet written.
    public func translation(gid: String, pageIndex: Int, modelSetKey: String) async throws -> PageTranslation? {
        let key = PageKey(gid: gid, modelSetKey: modelSetKey, pageIndex: pageIndex)
        await waitForQueuedDeletes()
        if let unwritten = pending[key] ?? inFlight[key] { return unwritten }
        return try await database.pageTranslation(gid: gid, pageIndex: pageIndex, modelSetKey: modelSetKey)
    }

    /// The pages of a gallery with a result for `modelSetKey`, including those not yet written,
    /// in order.
    public func translatedPageIndices(gid: String, modelSetKey: String) async throws -> [Int] {
        await waitForQueuedDeletes()
        // Taken before the read: a result written meanwhile is in one of the two.
        let unwritten = unwrittenPages(gid: gid, modelSetKey: modelSetKey)
        let stored = try await database.translatedPageIndices(gid: gid, modelSetKey: modelSetKey)
        return unwritten.isEmpty ? stored : Set(stored).union(unwritten).sorted()
    }

    /// How many pages of a gallery have a result for `modelSetKey`, including those not yet
    /// written: one count query when nothing of the gallery is waiting.
    public func translatedPageCount(gid: String, modelSetKey: String) async throws -> Int {
        await waitForQueuedDeletes()
        guard unwrittenPages(gid: gid, modelSetKey: modelSetKey).isEmpty else {
            return try await translatedPageIndices(gid: gid, modelSetKey: modelSetKey).count
        }
        return try await database.pageTranslationCount(gid: gid, modelSetKey: modelSetKey)
    }

    // MARK: - The queue

    private func unwrittenPages(gid: String, modelSetKey: String) -> Set<Int> {
        var pages = Set<Int>()
        for key in pending.keys where key.gid == gid && key.modelSetKey == modelSetKey {
            pages.insert(key.pageIndex)
        }
        for key in inFlight.keys where key.gid == gid && key.modelSetKey == modelSetKey {
            pages.insert(key.pageIndex)
        }
        return pages
    }

    private func waitForQueuedDeletes() async {
        while queuedDeletes > 0 {
            await waitUntilWritten()
        }
    }

    private func enqueueDelete(_ delete: @escaping @Sendable (AppDatabase) async throws -> Void) {
        queuedDeletes += 1
        enqueue { [database] in
            try await delete(database)
        } completion: { writer in
            writer.queuedDeletes -= 1
        }
    }

    private func enqueue(
        _ write: @escaping @Sendable () async throws -> Void,
        completion: @escaping @Sendable (isolated PageTranslationResultWriter) -> Void
    ) {
        let previous = lastWrite
        writeCount += 1
        lastWrite = Task {
            await previous?.value
            do {
                try await write()
            } catch {
                logger.error("Saving page translations failed: \(error)", category: "PageTranslation")
            }
            completion(self)
        }
    }
}
