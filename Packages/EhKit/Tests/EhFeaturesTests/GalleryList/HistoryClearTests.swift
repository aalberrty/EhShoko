import Dependencies
import EhCore
import EhDatabase
import EhModels
import EhTestSupport
import Foundation
import Testing
@testable import EhFeatures

/// Clear History takes what was translated of the pages read: their text, results not yet
/// written and the patch files.
@Suite struct HistoryClearTests {
    static let modelSet = PageTranslationModelSet.default.key

    @Test func clearingTheHistoryRemovesTranslatedPages() async throws {
        let database = try AppDatabase.makeInMemory()
        try await database.recordOpened(.stub("1"))
        try await database.savePageTranslations([Self.page(gid: "1", index: 1)])
        // A result still waiting for its batch when the history is cleared.
        let writer = PageTranslationResultWriter(database: database, logger: .console(), delay: .seconds(3_600))
        await writer.add(Self.page(gid: "1", index: 2))
        let directory = try TestDatabase.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let patches = PageTranslationPatchStore(directory: directory.appending(path: "PageTranslation"))
        let variant = PageTranslationPatchVariant(modelSet: .default, repaint: .lamaManga, renderVersion: 1)
        let file = try await patches.prepareToWrite(gid: "1", pageIndex: 1, variant: variant)
        try Data(repeating: 1, count: 4_096).write(to: file)
        await patches.didWrite(file)
        let model = withDependencies {
            $0.database = database
            $0.pageTranslationResultWriter = writer
            $0.pageTranslationPatchStore = patches
        } operation: {
            HistoryModel()
        }

        await model.clear()

        #expect(try await database.gallery(gid: "1") == nil)
        #expect(try await database.pageTranslationCount(gid: "1", modelSetKey: Self.modelSet) == 0)
        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(await patches.size() == 0)
        // The waiting result was dropped: a later batch writes nothing back.
        await writer.flush()
        await writer.waitUntilWritten()
        #expect(try await database.pageTranslationCount(gid: "1", modelSetKey: Self.modelSet) == 0)
        #expect(model.loadingState == .loading)
    }

    /// Without any override the two keys' test values are used, as when translation was never
    /// used: clearing succeeds and touches no patch folder.
    @Test func clearingWhenNothingWasTranslatedSucceeds() async throws {
        let env = try ListTestEnvironment()
        try await env.database.recordOpened(.stub("1"))
        let model = env.make { HistoryModel() }

        await model.clear()

        #expect(try await env.database.gallery(gid: "1") == nil)
        #expect(model.loadingState == .loading)
    }

    static func page(gid: String, index: Int) -> PageTranslation {
        PageTranslation(
            gid: gid, pageIndex: index, modelSetKey: modelSet, imageWidth: 1000, imageHeight: 1400,
            regions: [TranslatedRegion(
                box: FractionalRect(x: 0.25, y: 0.25, width: 0.125, height: 0.25), kind: .dialogue,
                isVertical: true, score: 0.75, source: "こんにちは", translation: "你好"
            )],
            createdAt: .now
        )
    }
}
