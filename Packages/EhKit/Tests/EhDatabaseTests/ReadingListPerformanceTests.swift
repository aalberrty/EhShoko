@testable import EhDatabase
import EhModels
import EhTestSupport
import Foundation
import GRDB
import Testing

/// The Continue and count queries against a large history: 10,000 opened galleries.
///
/// Each query is timed on its own, best of five, so the bounds hold on a loaded machine and
/// still catch a full decode of the history or a query per row, which take seconds at this
/// size. The plan test is the load-independent check: no sort of the history, no scan of
/// another table.
@Suite struct ReadingListPerformanceTests {
    static let historySize = 10_000

    /// Fills the history in one transaction. Every `startedEvery`-th gallery is started, every
    /// third of the rest is finished, the others were never read.
    private func makeDatabase(startedEvery: Int?) async throws -> AppDatabase {
        let database = try await TestDatabase.inMemory()
        try await database.writer.write { db in
            for index in 0..<Self.historySize {
                let gid = "\(index)"
                try GalleryRecord(gallery: SampleData.gallery(gid), lastOpenDate: SampleData.date(Double(index)))
                    .insert(db)
                let progress: Int? = if let startedEvery, index.isMultiple(of: startedEvery) {
                    1 + index % 40
                } else if index.isMultiple(of: 3) {
                    42
                } else {
                    nil
                }
                if let progress {
                    try db.execute(
                        sql: "INSERT INTO \(Schema.galleryState) (gid, readingProgress) VALUES (?, ?)",
                        arguments: [gid, progress]
                    )
                }
            }
        }
        return database
    }

    /// The best of `runs` timings of `work`, run in one read: the query's own cost, with as
    /// little of the machine's load in it as possible. Prints the best and the worst.
    private func bestTime<T: Sendable>(
        _ label: String, of database: AppDatabase, runs: Int = 5, _ work: @escaping @Sendable (Database) throws -> T
    ) async throws -> (T, Duration) {
        let (value, timings) = try await database.writer.read { db in
            let clock = ContinuousClock()
            var timings = [Duration]()
            func run() throws -> T {
                let start = clock.now
                let value = try work(db)
                timings.append(clock.now - start)
                return value
            }
            let value = try run()
            for _ in 1..<runs { _ = try run() }
            return (value, timings)
        }
        let best = timings.min() ?? .zero
        print("ReadingListPerformance \(label): best \(Self.format(best)), worst \(Self.format(timings.max() ?? .zero))")
        return (value, best)
    }

    private static func format(_ duration: Duration) -> String {
        duration.formatted(.units(allowed: [.milliseconds], fractionalPart: .show(length: 2)))
    }

    @Test func readingListOver10000Galleries() async throws {
        let database = try await makeDatabase(startedEvery: 10)

        let (items, best) = try await bestTime("reading list, 1,000 started", of: database) { db in
            try AppDatabase.readingList(limit: 10, in: db)
        }
        #expect(items.map(\.id) == (0..<10).map { "\(Self.historySize - 10 - $0 * 10)" })
        #expect(best < .milliseconds(500), "\(best)")

        // A page turn in the most recent gallery: the time from the write to the new value,
        // which includes the scheduling of the observation's task.
        let newest = try #require(items.first)
        let sequence = database.observeReadingList(limit: 10)
        let (first, next, update) = try await withTimeout {
            var iterator = sequence.makeAsyncIterator()
            let first = try await iterator.next()
            let clock = ContinuousClock()
            let start = clock.now
            try await database.updateReadingProgress(gid: newest.id, progress: newest.page + 1)
            let next = try await iterator.next()
            return (first, next, clock.now - start)
        }
        print("ReadingListPerformance progress write to new value: \(Self.format(update))")
        #expect(first == items)
        #expect(next?.first?.page == newest.page + 1)
        #expect(update < .seconds(30), "\(update)")
    }

    /// The worst case: nothing is in progress, so every row is looked at to find none.
    @Test func readingListWithNothingStarted() async throws {
        let database = try await makeDatabase(startedEvery: nil)
        let (items, best) = try await bestTime("reading list, nothing started", of: database) { db in
            try AppDatabase.readingList(limit: 10, in: db)
        }
        #expect(items.isEmpty)
        #expect(best < .milliseconds(500), "\(best)")
    }

    @Test func historyCountOver10000Galleries() async throws {
        let database = try await makeDatabase(startedEvery: 10)
        let (count, best) = try await bestTime("history count", of: database) { db in
            try GalleryRecord.fetchCount(db)
        }
        #expect(count == Self.historySize)
        #expect(best < .milliseconds(500), "\(best)")
        #expect(try await observe(database.observeHistoryCount(), changes: []) == [Self.historySize])
    }

    /// The reading progress of a list page (60 rows) and of a long History (600 rows), each in
    /// one read, against 10,000 stored galleries.
    @Test func readingProgressOfAPageOver10000Galleries() async throws {
        let database = try await makeDatabase(startedEvery: 10)
        let page = (0..<60).map { "\(Self.historySize - 1 - $0)" }
        let (progress, best) = try await bestTime("reading progress, 60 gids", of: database) { db in
            try AppDatabase.readingProgress(gids: page, in: db)
        }
        // Every 10th is started and every 3rd of the rest finished: index % 10 == 0 or % 3 == 0.
        let expected = page.filter { Int($0)!.isMultiple(of: 10) || Int($0)!.isMultiple(of: 3) }
        #expect(Set(progress.keys) == Set(expected))
        #expect(best < .milliseconds(100), "\(best)")

        let history = (0..<600).map { "\($0 * 7)" }
        let (long, longBest) = try await bestTime("reading progress, 600 gids", of: database) { db in
            try AppDatabase.readingProgress(gids: history, in: db)
        }
        #expect(!long.isEmpty)
        #expect(longBest < .milliseconds(500), "\(longBest)")
    }

    /// Each gid is a primary-key lookup: no scan of the state table.
    @Test func readingProgressLooksUpByKey() async throws {
        let database = try await makeDatabase(startedEvery: 10)
        let plan = try await database.writer.read { db in
            try Row.fetchAll(
                db, sql: "EXPLAIN QUERY PLAN " + AppDatabase.readingProgressSQL(count: 3), arguments: ["1", "2", "3"]
            ).map { $0["detail"] as String }
        }
        print("ReadingListPerformance progress plan: \(plan)")
        #expect(plan.contains { $0.contains("SEARCH") }, "\(plan)")
        #expect(!plan.contains { $0.hasPrefix("SCAN") }, "\(plan)")
    }

    /// The order comes from the `lastOpenDate` index and the other tables are read by key:
    /// no sort of the whole history, no scan of another table.
    @Test func readingListUsesTheOpenDateIndex() async throws {
        let database = try await makeDatabase(startedEvery: 10)
        let plan = try await database.writer.read { db in
            try Row.fetchAll(db, sql: "EXPLAIN QUERY PLAN " + AppDatabase.readingListSQL, arguments: [10])
                .map { $0["detail"] as String }
        }
        print("ReadingListPerformance plan: \(plan)")
        #expect(!plan.contains { $0.contains("TEMP B-TREE") }, "\(plan)")
        #expect(plan.contains { $0.contains("lastOpenDate") }, "\(plan)")
        #expect(!plan.contains { $0.hasPrefix("SCAN s") || $0.hasPrefix("SCAN d") }, "\(plan)")
    }
}
