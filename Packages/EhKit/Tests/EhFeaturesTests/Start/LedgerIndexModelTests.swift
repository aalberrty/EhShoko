import Dependencies
import EhCore
import EhDatabase
@testable import EhFeatures
import EhModels
import Foundation
import Testing

@MainActor
@Suite struct LedgerIndexModelTests {
    let database: AppDatabase
    /// What the clipboard's pattern detection answers, what it holds, and how often it was read.
    let hasProbableURL = LockIsolated(true)
    let clipboardURL = LockIsolated(URL(string: "https://e-hentai.org/g/1/abc/"))
    let urlReads = LockIsolated(0)

    init() throws {
        database = try AppDatabase.makeInMemory()
    }

    private func makeModel() -> LedgerIndexModel {
        withDependencies {
            $0.database = database
            $0.clipboardClient = ClipboardClient(
                changeCount: { 0 },
                url: { [urlReads, clipboardURL] in
                    urlReads.withValue { $0 += 1 }
                    return clipboardURL.value
                },
                copyText: { _ in }, copyImage: { _ in },
                hasProbableURL: { [hasProbableURL] in hasProbableURL.value }
            )
        } operation: {
            LedgerIndexModel()
        }
    }

    // MARK: The pasted link

    @Test func aPastedGalleryOrImagePageLinkComesBackAsTheAppsOwnLink() async {
        let model = makeModel()
        // The shell opens it as it opens a shared link.
        #expect(await model.pastedGalleryLink() == URL(string: "ehshoko://e-hentai.org/g/1/abc/"))

        clipboardURL.setValue(URL(string: "https://exhentai.org/s/0123456789/1-2"))
        #expect(await model.pastedGalleryLink() == URL(string: "ehshoko://exhentai.org/s/0123456789/1-2"))
        #expect(urlReads.value == 2)
    }

    @Test func aLinkTheAppCannotOpenGivesNone() async {
        let model = makeModel()
        for link in ["https://example.com/g/1/abc/", "http://e-hentai.org/g/1/abc/", "https://e-hentai.org/tag/glasses"] {
            clipboardURL.setValue(URL(string: link))
            #expect(await model.pastedGalleryLink() == nil, "\(link)")
        }
        clipboardURL.setValue(nil)
        #expect(await model.pastedGalleryLink() == nil)
    }

    @Test func withoutAProbableLinkTheClipboardIsNotRead() async {
        hasProbableURL.setValue(false)
        #expect(await makeModel().pastedGalleryLink() == nil)
        // Reading would show the system's paste prompt.
        #expect(urlReads.value == 0)
    }

    // MARK: Observations

    @Test func followsHistorysSizeAndTheQuickSearches() async throws {
        let model = makeModel()
        #expect(model.historyCount == nil)
        let history = Task { await model.observeHistoryCount() }
        let words = Task { await model.observeQuickSearches() }
        defer {
            history.cancel()
            words.cancel()
        }
        try await eventually { model.historyCount == 0 }

        try await database.recordOpened(makeGallery(gid: "1"))
        try await database.recordOpened(makeGallery(gid: "2"))
        try await eventually { model.historyCount == 2 }

        let word = QuickSearchWord(name: "Glasses", content: "female:glasses$")
        try await database.insertQuickSearchWord(word)
        try await eventually { model.quickSearches == [word] }
    }
}
