@testable import EhCore
import EhModels
import Foundation
import Testing

@MainActor @Suite struct UserStoreFavoriteFolderTests {
    private static let folders = (0...9).map { index in
        FavoriteFolder(index: index, name: index == 2 ? "To read" : "Favorites \(index)", count: index * 10)
    }

    @Test func countsAreUnknownUntilAFavoritesPageIsLoaded() {
        let store = UserStore(storage: .ephemeral())
        #expect(store.favoriteFolderCounts.isEmpty)
        #expect(store.favoriteTotalCount == nil)
    }

    @Test func aFavoritesPageGivesCountsAndNames() {
        let storage = PreferenceStorage.ephemeral()
        let store = UserStore(storage: storage)
        store.updateFavoriteFolders(Self.folders)

        #expect(store.favoriteFolderCounts == Dictionary(uniqueKeysWithValues: (0...9).map { ($0, $0 * 10) }))
        #expect(store.favoriteTotalCount == 450)
        #expect(store.customFavoriteCategoryName(index: 2) == "To read")
        #expect(store.customFavoriteCategoryName(index: 3) == nil)

        // Names persist with the profile; counts are for this session only.
        store.waitForPendingWrites()
        let reloaded = UserStore(storage: storage)
        #expect(reloaded.customFavoriteCategoryName(index: 2) == "To read")
        #expect(reloaded.favoriteFolderCounts.isEmpty)
    }

    @Test func aLaterPageReplacesTheCounts() {
        let store = UserStore(storage: .ephemeral())
        store.updateFavoriteFolders(Self.folders)
        store.updateFavoriteFolders([FavoriteFolder(index: 0, name: "Favorites 0", count: 1)])
        #expect(store.favoriteFolderCounts == [0: 1])
        // Names of folders the page did not list are kept.
        #expect(store.customFavoriteCategoryName(index: 2) == "To read")
    }

    @Test func aPageWithoutFoldersChangesNothing() {
        let store = UserStore(storage: .ephemeral())
        store.updateFavoriteFolders(Self.folders)
        let observed = changeIsObserved(reading: { _ = store.favoriteFolderCounts }) {
            store.updateFavoriteFolders([])
        }
        #expect(!observed)
        #expect(store.favoriteTotalCount == 450)
    }

    @Test func theSameCountsDoNotInvalidateObservers() {
        let store = UserStore(storage: .ephemeral())
        store.updateFavoriteFolders(Self.folders)
        let countsObserved = changeIsObserved(reading: { _ = store.favoriteFolderCounts }) {
            store.updateFavoriteFolders(Self.folders)
        }
        let namesObserved = changeIsObserved(reading: { _ = store.favoriteCategories }) {
            store.updateFavoriteFolders(Self.folders)
        }
        #expect(!countsObserved)
        #expect(!namesObserved)
    }

    @Test func signingOutForgetsTheCounts() {
        let store = UserStore(storage: .ephemeral())
        store.updateFavoriteFolders(Self.folders)
        store.clear()
        #expect(store.favoriteFolderCounts.isEmpty)
        #expect(store.favoriteCategories == nil)
    }
}
