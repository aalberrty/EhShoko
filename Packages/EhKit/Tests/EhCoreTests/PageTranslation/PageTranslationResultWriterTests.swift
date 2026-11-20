import EhDatabase
import EhModels
import EhTestSupport
import Foundation
import Testing
@testable import EhCore

@Suite struct PageTranslationResultWriterTests {
    static let modelSet = PageTranslationModelSet.default.key
    static let otherModelSet = PageTranslationModelSet(detector: .v4s).key

    /// A writer whose batches are only written by `flush()`: its delay outlasts any test.
    static func writer(_ database: AppDatabase, delay: Duration = .seconds(3_600)) -> PageTranslationResultWriter {
        PageTranslationResultWriter(database: database, logger: .console(), delay: delay)
    }

    @Test func aRunOfPagesIsOneTransaction() async throws {
        let database = try await TestDatabase.inMemory()
        let writer = Self.writer(database)
        for index in 1...5 {
            await writer.add(Self.page(gid: "1", index: index))
        }
        #expect(try await database.pageTranslationCount(gid: "1", modelSetKey: Self.modelSet) == 0)

        await writer.flush()
        await writer.waitUntilWritten()
        #expect(await writer.writeCount == 1)
        #expect(try await database.translatedPageIndices(gid: "1", modelSetKey: Self.modelSet) == [1, 2, 3, 4, 5])
    }

    @Test func theDelayWritesABurstOnItsOwn() async throws {
        let database = try await TestDatabase.inMemory()
        let writer = Self.writer(database, delay: .seconds(1))
        for index in 1...3 {
            await writer.add(Self.page(gid: "1", index: index))
        }
        let deadline = ContinuousClock.now + .seconds(60)
        while await writer.writeCount == 0, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        await writer.waitUntilWritten()
        #expect(await writer.writeCount == 1)
        #expect(try await database.pageTranslationCount(gid: "1", modelSetKey: Self.modelSet) == 3)
    }

    @Test func flushingWithNothingQueuedWritesNothing() async throws {
        let writer = Self.writer(try await TestDatabase.inMemory())
        await writer.flush()
        await writer.waitUntilWritten()
        #expect(await writer.writeCount == 0)
    }

    @Test func aPageQueuedAgainKeepsItsLatestResult() async throws {
        let database = try await TestDatabase.inMemory()
        let writer = Self.writer(database)
        await writer.add(Self.page(gid: "1", index: 1, translation: "旧"))
        await writer.add(Self.page(gid: "1", index: 1, translation: "新"))
        await writer.flush()
        await writer.waitUntilWritten()
        let stored = try await database.pageTranslation(gid: "1", pageIndex: 1, modelSetKey: Self.modelSet)
        #expect(stored?.regions.first?.translation == "新")
    }

    @Test func readsFindResultsNotYetWritten() async throws {
        let database = try await TestDatabase.inMemory()
        try await database.savePageTranslations([Self.page(gid: "1", index: 1), Self.page(gid: "1", index: 4)])
        let writer = Self.writer(database)
        let queued = Self.page(gid: "1", index: 2)
        await writer.add(queued)
        await writer.add(Self.page(gid: "1", index: 4))
        await writer.add(Self.page(gid: "1", index: 3, modelSet: Self.otherModelSet))

        #expect(try await writer.translation(gid: "1", pageIndex: 2, modelSetKey: Self.modelSet) == queued)
        #expect(try await writer.translation(gid: "1", pageIndex: 1, modelSetKey: Self.modelSet) != nil)
        #expect(try await writer.translation(gid: "1", pageIndex: 3, modelSetKey: Self.modelSet) == nil)
        #expect(try await writer.translatedPageIndices(gid: "1", modelSetKey: Self.modelSet) == [1, 2, 4])
        #expect(try await writer.translatedPageCount(gid: "1", modelSetKey: Self.modelSet) == 3)
        #expect(try await writer.translatedPageCount(gid: "1", modelSetKey: Self.otherModelSet) == 1)
        #expect(try await writer.translatedPageCount(gid: "2", modelSetKey: Self.modelSet) == 0)

        // While the batch is being written, and after.
        await writer.flush()
        #expect(try await writer.translatedPageIndices(gid: "1", modelSetKey: Self.modelSet) == [1, 2, 4])
        await writer.waitUntilWritten()
        #expect(try await writer.translatedPageCount(gid: "1", modelSetKey: Self.modelSet) == 3)
        #expect(try await writer.translation(gid: "1", pageIndex: 2, modelSetKey: Self.modelSet) == queued)
    }

    @Test func deletingAGalleryForgetsItsQueuedResults() async throws {
        let database = try await TestDatabase.inMemory()
        try await database.savePageTranslations([Self.page(gid: "1", index: 1), Self.page(gid: "2", index: 1)])
        let writer = Self.writer(database)
        await writer.add(Self.page(gid: "1", index: 2))
        await writer.add(Self.page(gid: "2", index: 2))

        await writer.deleteTranslations(gid: "1")
        #expect(try await writer.translatedPageCount(gid: "1", modelSetKey: Self.modelSet) == 0)
        await writer.flush()
        await writer.waitUntilWritten()
        #expect(try await database.pageTranslationCount(gid: "1", modelSetKey: Self.modelSet) == 0)
        #expect(try await database.translatedPageIndices(gid: "2", modelSetKey: Self.modelSet) == [1, 2])
    }

    @Test func aDeleteIsNotOvertakenByAnEarlierSave() async throws {
        let database = try await TestDatabase.inMemory()
        let writer = Self.writer(database)
        await writer.add(Self.page(gid: "1", index: 1))
        await writer.flush()
        await writer.deleteTranslations(gid: "1")
        await writer.waitUntilWritten()
        #expect(try await database.pageTranslationCount(gid: "1", modelSetKey: Self.modelSet) == 0)
        #expect(await writer.writeCount == 2)
    }

    @Test func discardingDropsWhatIsWaiting() async throws {
        let database = try await TestDatabase.inMemory()
        let writer = Self.writer(database)
        await writer.add(Self.page(gid: "1", index: 1))
        await writer.discardUnwritten()
        #expect(try await writer.translatedPageCount(gid: "1", modelSetKey: Self.modelSet) == 0)
        await writer.flush()
        await writer.waitUntilWritten()
        #expect(await writer.writeCount == 0)
        // Results added afterwards are written as usual.
        await writer.add(Self.page(gid: "1", index: 2))
        await writer.flush()
        await writer.waitUntilWritten()
        #expect(try await database.translatedPageIndices(gid: "1", modelSetKey: Self.modelSet) == [2])
    }

    /// What Clear History relies on: once `discardUnwritten()` returns, no batch made before it
    /// commits, so rows deleted then stay deleted. A large batch makes a save that would still
    /// be running likely to commit after the delete.
    @Test func noBatchFromBeforeADiscardCommitsAfterIt() async throws {
        let database = try await TestDatabase.inMemory()
        let writer = Self.writer(database)
        for index in 1...400 {
            await writer.add(Self.page(gid: "1", index: index))
        }
        await writer.flush()
        await writer.add(Self.page(gid: "2", index: 1))
        await writer.discardUnwritten()
        try await database.deleteAllPageTranslations()
        await writer.flush()
        await writer.waitUntilWritten()
        #expect(try await database.pageTranslationCount(gid: "1", modelSetKey: Self.modelSet) == 0)
        #expect(try await database.pageTranslationCount(gid: "2", modelSetKey: Self.modelSet) == 0)
    }

    @Test func removingEverythingTakesRowsWaitingResultsAndPatchFiles() async throws {
        let database = try await TestDatabase.inMemory()
        try await database.savePageTranslations([Self.page(gid: "1", index: 1)])
        let writer = Self.writer(database)
        await writer.add(Self.page(gid: "2", index: 1))
        let (patches, directory) = try await Self.patchStoreWithAFile()
        defer { try? FileManager.default.removeItem(at: directory.deletingLastPathComponent()) }

        try await writer.removeAll(patchStore: patches)

        #expect(try await writer.translatedPageCount(gid: "2", modelSetKey: Self.modelSet) == 0)
        await writer.flush()
        await writer.waitUntilWritten()
        #expect(try await database.pageTranslationCount(gid: "1", modelSetKey: Self.modelSet) == 0)
        #expect(try await database.pageTranslationCount(gid: "2", modelSetKey: Self.modelSet) == 0)
        #expect(!FileManager.default.fileExists(atPath: directory.path))
        #expect(await patches.size() == 0)
    }

    @Test func removingEverythingWhenNothingWasTranslatedSucceeds() async throws {
        let writer = Self.writer(try await TestDatabase.inMemory())
        let patches = PageTranslationPatchStore(
            directory: URL.temporaryDirectory.appending(path: "Missing-\(UUID().uuidString)", directoryHint: .isDirectory)
        )
        try await writer.removeAll(patchStore: patches)
        #expect(await patches.size() == 0)
    }

    @Test func expiryWritesWhatIsQueuedAndKeepsTheCurrentModelSet() async throws {
        let database = try await TestDatabase.inMemory()
        let now = Date(timeIntervalSinceReferenceDate: 100 * 86_400)
        let recent = now.addingTimeInterval(-86_400)
        let old = now.addingTimeInterval(-40 * 86_400)
        try await database.savePageTranslations([
            Self.page(gid: "1", index: 1, createdAt: old),
            Self.page(gid: "2", index: 1, modelSet: Self.otherModelSet, createdAt: recent)
        ])
        let writer = Self.writer(database)
        await writer.add(Self.page(gid: "3", index: 1, createdAt: recent))
        await writer.add(Self.page(gid: "3", index: 2, modelSet: Self.otherModelSet, createdAt: recent))

        await writer.removeExpired(keepingModelSetKey: Self.modelSet, now: now)
        #expect(try await writer.translatedPageCount(gid: "3", modelSetKey: Self.otherModelSet) == 0)
        await writer.waitUntilWritten()
        #expect(try await database.pageTranslationCount(gid: "1", modelSetKey: Self.modelSet) == 0)
        #expect(try await database.pageTranslationCount(gid: "2", modelSetKey: Self.otherModelSet) == 0)
        #expect(try await database.translatedPageIndices(gid: "3", modelSetKey: Self.modelSet) == [1])
        #expect(try await database.pageTranslationCount(gid: "3", modelSetKey: Self.otherModelSet) == 0)
    }

    /// A patch store over a new temporary folder that holds one patch file.
    static func patchStoreWithAFile() async throws -> (PageTranslationPatchStore, URL) {
        let directory = try TestDatabase.makeTemporaryDirectory().appending(path: "PageTranslation")
        let store = PageTranslationPatchStore(directory: directory)
        let variant = PageTranslationPatchVariant(modelSet: .default, repaint: .lamaManga, renderVersion: 1)
        let url = try await store.prepareToWrite(gid: "1", pageIndex: 1, variant: variant)
        try Data(repeating: 1, count: 4_096).write(to: url)
        await store.didWrite(url)
        return (store, directory)
    }

    static func page(
        gid: String, index: Int, modelSet: String = modelSet, translation: String = "你好",
        createdAt: Date = Date(timeIntervalSinceReferenceDate: 1_000)
    ) -> PageTranslation {
        PageTranslation(
            gid: gid, pageIndex: index, modelSetKey: modelSet, imageWidth: 1000, imageHeight: 1400,
            regions: [TranslatedRegion(
                box: FractionalRect(x: 0.25, y: 0.25, width: 0.125, height: 0.25), kind: .dialogue,
                isVertical: true, score: 0.75, source: "こんにちは", translation: translation
            )],
            createdAt: createdAt
        )
    }
}
