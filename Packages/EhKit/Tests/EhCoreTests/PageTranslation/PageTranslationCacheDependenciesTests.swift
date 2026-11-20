import Dependencies
import EhDatabase
import EhModels
import EhTestSupport
import Foundation
import Testing
@testable import EhCore

@Suite struct PageTranslationCacheDependenciesTests {
    @Test func theWritersTestValueWritesToTheTestsDatabase() async throws {
        let database = try await TestDatabase.inMemory()
        let writer = withDependencies {
            $0.database = database
        } operation: {
            @Dependency(\.pageTranslationResultWriter) var writer
            return writer
        }
        await writer.add(PageTranslationResultWriterTests.page(gid: "1", index: 1))
        await writer.flush()
        await writer.waitUntilWritten()
        let key = PageTranslationModelSet.default.key
        #expect(try await database.pageTranslationCount(gid: "1", modelSetKey: key) == 1)
    }

    @Test func eachIsMadeOnceAndReadAgainAsTheSameObject() {
        @Dependency(\.pageTranslationResultWriter) var writer
        @Dependency(\.pageTranslationPatchStore) var patches
        let firstWriter = writer, firstPatches = patches
        #expect(firstWriter === writer)
        #expect(firstPatches === patches)
    }

    @Test func thePatchStoresTestValueHasAFolderOfItsOwnThatDoesNotExistYet() async {
        @Dependency(\.pageTranslationPatchStore) var patches
        #expect(patches.directory.path.hasPrefix(URL.temporaryDirectory.path))
        #expect(!FileManager.default.fileExists(atPath: patches.directory.path))
        #expect(await patches.size() == 0)
    }

    @Test func theLivePatchStoreIsInCaches() {
        #expect(PageTranslationPatchStore.liveValue.directory == PageTranslationPatchStore.defaultDirectory)
        #expect(PageTranslationPatchStore.defaultDirectory.path.hasSuffix("Caches/PageTranslation"))
    }
}
