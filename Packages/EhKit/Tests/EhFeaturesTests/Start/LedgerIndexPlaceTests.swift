import EhFeatures
import EhModels
import Testing

/// Which row the Index's iPad column shows as chosen for the stack's first entry.
@MainActor
@Suite struct LedgerIndexPlaceTests {
    @Test func anEmptyPathChoosesFrontPage() {
        #expect(LedgerIndexPlace(base: nil) == .list(.frontpage))
    }

    @Test func aListAtTheBottomIsChosen() {
        for kind in [GalleryListKind.frontpage, .popular, .watched, .toplists, .history] {
            #expect(LedgerIndexPlace(base: .galleryList(kind)) == .list(kind))
        }
    }

    @Test func aFolderAtTheBottomIsChosenByItsNumber() {
        #expect(LedgerIndexPlace(base: .favoritesFolder(3)) == .folder(3))
        #expect(LedgerIndexPlace(base: .favoritesFolder(-1)) == .folder(-1))
    }

    @Test func theLibraryChoosesNoRow() {
        #expect(LedgerIndexPlace(base: .galleryList(.favorites)) == nil)
    }

    @Test func aSearchOrSettingsOverFrontPageKeepsFrontPageChosen() {
        #expect(LedgerIndexPlace(base: .search(keyword: "tag")) == .list(.frontpage))
        #expect(LedgerIndexPlace(base: .typedSearch(keyword: "tag")) == .list(.frontpage))
        #expect(LedgerIndexPlace(base: .listSearch(.everywhere, keyword: "tag")) == .list(.frontpage))
    }
}
