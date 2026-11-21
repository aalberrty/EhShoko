import EhCore
@testable import EhFeatures
import EhModels
import Foundation
import Testing

@Suite struct ReaderTranslationWindowTests {
    @Test func thePageOnScreenThenThreeAheadThenThePageBefore() {
        let window = ReaderTranslationWindow(currentPage: 5, pageCount: 20)
        #expect(window.onScreen == [5])
        #expect(window.ahead == [6, 7, 8])
        #expect(window.behind == [4])
        #expect(window.pages == [5, 6, 7, 8, 4])
    }

    @Test func nothingBeforeTheFirstPageOrAfterTheLast() {
        #expect(ReaderTranslationWindow(currentPage: 1, pageCount: 20).behind.isEmpty)
        #expect(ReaderTranslationWindow(currentPage: 19, pageCount: 20).ahead == [20])
        let last = ReaderTranslationWindow(currentPage: 20, pageCount: 20)
        #expect(last.ahead.isEmpty)
        #expect(last.pages == [20, 19])
        #expect(ReaderTranslationWindow(currentPage: 1, pageCount: 1).pages == [1])
    }

    @Test func aPageOutsideTheGalleryAsksForNothing() {
        #expect(ReaderTranslationWindow(currentPage: 0, pageCount: 20).pages.isEmpty)
        #expect(ReaderTranslationWindow(currentPage: 21, pageCount: 20).pages.isEmpty)
        #expect(ReaderTranslationWindow(currentPage: 1, pageCount: 0).pages.isEmpty)
    }

    @Test func bothPagesOfASpreadAreOnScreen() {
        let window = ReaderTranslationWindow(currentPage: 6, pageCount: 20, shown: [6, 7])
        #expect(window.onScreen == [6, 7])
        #expect(window.ahead == [8, 9, 10])
        #expect(window.behind == [5])
        #expect(window.pages == [6, 7, 8, 9, 10, 5])

        // The last spread reports its second page as current: reading order all the same.
        let last = ReaderTranslationWindow(currentPage: 20, pageCount: 20, shown: [19, 20])
        #expect(last.onScreen == [19, 20])
        #expect(last.ahead.isEmpty)
        #expect(last.behind == [18])
    }

    @Test func theStripsPagesAreOnScreenNearestFirst() {
        let window = ReaderTranslationWindow(currentPage: 6, pageCount: 20, shown: [6, 7, 5])
        #expect(window.onScreen == [6, 7, 5])
        #expect(window.ahead == [8, 9, 10])
        #expect(window.behind == [4])

        // A strip of short pages: only the nearest count as on screen, the rest are ahead.
        let short = ReaderTranslationWindow(currentPage: 3, pageCount: 20, shown: [3, 4, 5, 6, 7, 8, 2])
        #expect(short.onScreen == [3, 4, 5, 6])
        #expect(short.ahead == [7, 8, 9])
        #expect(short.behind == [2])
    }

    @Test func shownPagesWithoutTheCurrentPageDoNotCount() {
        // The reader turned the page and the engine has not said yet what it shows, or it has
        // not said anything at all.
        #expect(ReaderTranslationWindow(currentPage: 8, pageCount: 20, shown: [6, 7])
            == ReaderTranslationWindow(currentPage: 8, pageCount: 20))
        #expect(ReaderTranslationWindow(currentPage: 20, pageCount: 20, shown: [])
            == ReaderTranslationWindow(currentPage: 20, pageCount: 20))
        // Pages that do not exist and pages named twice are dropped.
        #expect(ReaderTranslationWindow(currentPage: 20, pageCount: 20, shown: [20, 21, 20, 0]).onScreen == [20])
    }

    @Test func aPageWithoutItsImageAddressIsLeftOut() {
        let url = { (page: Int) in URL(string: "https://img.example/\(page).jpg")! }
        let window = ReaderTranslationWindow(currentPage: 5, pageCount: 20)
            .request { $0 == 7 ? nil : url($0) }
        #expect(window.onScreen == [PageTranslationPage(index: 5, imageURL: url(5))])
        #expect(window.ahead.map(\.index) == [6, 8])
        #expect(window.behind == [PageTranslationPage(index: 4, imageURL: url(4))])

        let unresolved = ReaderTranslationWindow(currentPage: 5, pageCount: 20).request { _ in nil }
        #expect(unresolved.isEmpty)
    }
}

@Suite struct ReaderTranslationAvailabilityTests {
    @Test func eachStateOfTheModelSet() {
        let progress = ModelTransferProgress(completedBytes: 10, totalBytes: 40)
        let table: [(ModelSetState, ReaderTranslationAvailability)] = [
            (.ready, .ready),
            (.missing(bytes: 100), .needsModels),
            // No source offers a model: the sheet explains it, the gallery stays translatable.
            (.unavailable, .needsModels),
            (.failed(.checksumMismatch), .needsModels),
            (.downloading(progress), .installing(progress)),
            (.waitingForConnection(progress), .installing(progress)),
            (.paused(progress), .installing(progress)),
            (.preparing, .installing(nil))
        ]
        for (state, availability) in table {
            #expect(ReaderTranslationAvailability(state) == availability, "\(state)")
        }
    }

    @Test func theSitesLanguage() {
        #expect(!ReaderTranslationLanguage.isOtherLanguage(site: nil, titles: []))
        #expect(!ReaderTranslationLanguage.isOtherLanguage(site: .japanese, titles: []))
        #expect(!ReaderTranslationLanguage.isOtherLanguage(site: .invalid, titles: []))
        #expect(ReaderTranslationLanguage.isOtherLanguage(site: .english, titles: []))
        #expect(ReaderTranslationLanguage.isOtherLanguage(site: .chinese, titles: []))
        #expect(ReaderTranslationLanguage.isOtherLanguage(site: .other, titles: []))
    }

    @Test func theTitlesLanguageGroup() {
        func isOther(_ title: String) -> Bool {
            ReaderTranslationLanguage.isOtherLanguage(site: nil, titles: [TitleParser.parse(title)])
        }
        #expect(isOther("[Circle (Artist)] Title [English]"))
        #expect(isOther("[Circle (Artist)] Title [中国翻訳]"))
        #expect(!isOther("[Circle (Artist)] Title"))
        #expect(!isOther("(C99) [Circle (Artist)] Title (Parody)"))
        // The site says Japanese and the title another language: the title wins.
        #expect(ReaderTranslationLanguage.isOtherLanguage(
            site: .japanese, titles: [TitleParser.parse("[Circle (Artist)] Title [English]")]
        ))
    }
}
