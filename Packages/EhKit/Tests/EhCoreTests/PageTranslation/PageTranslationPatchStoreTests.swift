import EhModels
import EhTestSupport
import Foundation
import Testing
@testable import EhCore

@Suite struct PageTranslationPatchStoreTests {
    static let variant = PageTranslationPatchVariant(modelSet: .default, repaint: .lamaManga, renderVersion: 1)
    static let otherVariant = PageTranslationPatchVariant(modelSet: .default, repaint: .off, renderVersion: 1)
    /// Files are written in whole blocks, so a file's size on disk is its length.
    static let fileSize = 8_192

    @Test func filesAreKeptByGalleryVariantAndPage() throws {
        let directory = URL(filePath: "/tmp/PageTranslation", directoryHint: .isDirectory)
        let store = PageTranslationPatchStore(directory: directory)
        #expect(Self.variant.folderName == "k2xl768.cpt2.jmt1.t1.lamamanga.r1")
        #expect(store.fileURL(gid: "123", pageIndex: 7, variant: Self.variant).path
            == "/tmp/PageTranslation/123/k2xl768.cpt2.jmt1.t1.lamamanga.r1/7.patch")
        // A gid that is not digits cannot reach outside the store.
        let odd = store.fileURL(gid: "../x", pageIndex: 1, variant: Self.variant)
        #expect(odd.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().path
            == directory.path)
        #expect(odd.pathComponents.contains("..") == false)
    }

    @Test func measuresWhatIsWritten() async throws {
        let (store, directory) = try Self.makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        #expect(await store.size() == 0)
        try await Self.write(store, gid: "1", pages: 1...3)
        try await Self.write(store, gid: "2", pages: 1...2)
        #expect(await store.size() == 5 * Self.fileSize)
    }

    @Test func overTheLimitTheGalleryUsedLongestAgoGoesFirst() async throws {
        // Three galleries of four pages against a limit of ten: the eleventh file starts an
        // eviction, which must come down to eight.
        let (store, directory) = try Self.makeStore(limit: 10 * Self.fileSize)
        defer { try? FileManager.default.removeItem(at: directory) }
        try await Self.write(store, gid: "1", pages: 1...4)
        await store.markUsed(gid: "1", at: Self.day(2))
        try await Self.write(store, gid: "2", pages: 1...4)
        await store.markUsed(gid: "2", at: Self.day(1))
        try await Self.write(store, gid: "3", pages: 1...4, lastUsed: Self.day(3))

        #expect(Self.galleries(in: directory) == ["1", "3"])
        #expect(await store.size() == 8 * Self.fileSize)
    }

    @Test func theGalleryUsedLastIsNeverRemoved() async throws {
        let (store, directory) = try Self.makeStore(limit: 2 * Self.fileSize)
        defer { try? FileManager.default.removeItem(at: directory) }
        try await Self.write(store, gid: "1", pages: 1...1, lastUsed: Self.day(1))
        try await Self.write(store, gid: "2", pages: 1...5, lastUsed: Self.day(2))
        #expect(Self.galleries(in: directory) == ["2"])
        #expect(await store.size() == 5 * Self.fileSize)
    }

    @Test func evictionMeasuresAgainBeforeRemoving() async throws {
        // The same page written three times is counted three times until eviction measures.
        let (store, directory) = try Self.makeStore(limit: 4 * Self.fileSize)
        defer { try? FileManager.default.removeItem(at: directory) }
        try await Self.write(store, gid: "1", pages: 1...2, lastUsed: Self.day(1))
        for _ in 0..<3 {
            try await Self.write(store, gid: "2", pages: 1...1, lastUsed: Self.day(2))
        }
        #expect(Self.galleries(in: directory) == ["1", "2"])
    }

    @Test func expiryRemovesOtherVariantsAndGalleriesNotUsedLately() async throws {
        let (store, directory) = try Self.makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        try await Self.write(store, gid: "1", pages: 1...2, lastUsed: Self.day(95))
        try await Self.write(store, gid: "1", pages: 1...2, variant: Self.otherVariant, lastUsed: Self.day(95))
        try await Self.write(store, gid: "2", pages: 1...2, lastUsed: Self.day(50))
        try await Self.write(store, gid: "3", pages: 1...1, variant: Self.otherVariant, lastUsed: Self.day(99))

        await store.removeExpired(keeping: Self.variant, notUsedWithin: 30 * 86_400, now: Self.day(100))
        #expect(Self.galleries(in: directory) == ["1", "3"])
        #expect(Self.folders(in: directory.appending(path: "1")) == [Self.variant.folderName])
        #expect(Self.folders(in: directory.appending(path: "3")).isEmpty)
        #expect(await store.size() == 2 * Self.fileSize)
        // Removing a variant did not make the gallery look used now.
        let date = try directory.appending(path: "1").resourceValues(forKeys: [.contentModificationDateKey])
        #expect(date.contentModificationDate == Self.day(95))
    }

    @Test func removesOneGalleryOrEverything() async throws {
        let (store, directory) = try Self.makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        try await Self.write(store, gid: "1", pages: 1...2)
        try await Self.write(store, gid: "2", pages: 1...1)
        await store.removeGallery(gid: "1")
        #expect(Self.galleries(in: directory) == ["2"])
        #expect(await store.size() == Self.fileSize)

        await store.removeAll()
        #expect(await store.size() == 0)
        // Writing after a clear makes the folders again.
        try await Self.write(store, gid: "3", pages: 1...1)
        #expect(await store.size() == Self.fileSize)
    }

    // MARK: - Helpers

    static func makeStore(limit: Int = PageTranslationPatchStore.defaultLimit) throws
        -> (PageTranslationPatchStore, URL) {
        let directory = try TestDatabase.makeTemporaryDirectory().appending(path: "PageTranslation")
        return (PageTranslationPatchStore(directory: directory, limit: limit), directory)
    }

    /// Writes a file for each page as the service would: prepare, write, report. The gallery's
    /// date is set before the last page is reported, so eviction sees it.
    static func write(
        _ store: PageTranslationPatchStore, gid: String, pages: ClosedRange<Int>,
        variant: PageTranslationPatchVariant = variant, lastUsed: Date? = nil
    ) async throws {
        for page in pages {
            let url = try await store.prepareToWrite(gid: gid, pageIndex: page, variant: variant)
            try Data(repeating: UInt8(page), count: fileSize).write(to: url, options: .atomic)
            if let lastUsed {
                await store.markUsed(gid: gid, at: lastUsed)
            }
            await store.didWrite(url)
        }
    }

    static func galleries(in directory: URL) -> [String] {
        folders(in: directory)
    }

    static func folders(in directory: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []).sorted()
    }

    static func day(_ number: Double) -> Date {
        Date(timeIntervalSinceReferenceDate: number * 86_400)
    }
}
