@testable import EhFeatures
import EhModels
import EhTestSupport
import Foundation
import Testing

/// A favourites folder drops the galleries removed or moved away from this list.
@MainActor
@Suite struct GalleryListFavoritesTests {
    private func loadedFolder(_ folder: Int) async throws -> (ListTestEnvironment, GalleryListModel) {
        let env = try ListTestEnvironment()
        env.transport.on(.any, reply: .fixture(ListFixture.favorites))
        let model = env.make { GalleryListModel(source: .favorites(category: folder, keyword: "", sortOrder: nil)) }
        await model.loadIfNeeded()
        #expect(model.entries.count > 3)
        return (env, model)
    }

    @Test func aRemovedFavouriteLeavesEveryFolder() async throws {
        let (_, model) = try await loadedFolder(-1)
        let removed = model.entries[1].id
        let count = model.entries.count

        model.applyFavoriteChanges([removed: .removed])

        #expect(model.entries.count == count - 1)
        #expect(!model.entries.map(\.id).contains(removed))
        #expect(!model.visibleEntries.map(\.id).contains(removed))
    }

    @Test func aMovedFavouriteLeavesItsFolderButNotAll() async throws {
        let (_, folder) = try await loadedFolder(3)
        let moved = folder.entries[0].id
        folder.applyFavoriteChanges([moved: .added(folder: 5)])
        #expect(!folder.entries.map(\.id).contains(moved))

        let (_, all) = try await loadedFolder(-1)
        let count = all.entries.count
        all.applyFavoriteChanges([all.entries[0].id: .added(folder: 5)])
        #expect(all.entries.count == count)
    }

    /// Favourited again into the folder it is in: it stays.
    @Test func aFavouriteAddedToTheSameFolderStays() async throws {
        let (_, model) = try await loadedFolder(3)
        let count = model.entries.count

        model.applyFavoriteChanges([model.entries[0].id: .added(folder: 3)])

        #expect(model.entries.count == count)
    }

    @Test func otherListsKeepTheirRows() async throws {
        let env = try ListTestEnvironment()
        env.transport.on(.any, reply: .fixture(ListFixture.frontpage))
        let model = env.make { GalleryListModel(source: .frontpage) }
        await model.loadIfNeeded()
        let ids = model.entries.map(\.id)

        model.applyFavoriteChanges([ids[0]: .removed])

        #expect(model.entries.map(\.id) == ids)
    }

    /// The whole table is passed each time; what was dropped stays dropped, and a later page
    /// that lists it again does not bring it back.
    @Test func applyingTheTableAgainChangesNothing() async throws {
        let (_, model) = try await loadedFolder(-1)
        let removed = model.entries[0].id
        model.applyFavoriteChanges([removed: .removed])
        let after = model.entries.map(\.id)

        model.applyFavoriteChanges([removed: .removed])
        await model.loadMore()

        #expect(model.entries.map(\.id).prefix(after.count) == after[...])
        #expect(!model.entries.map(\.id).contains(removed))
    }

    @Test func droppingEveryRowAsksTheSiteAgain() async throws {
        let (env, model) = try await loadedFolder(2)
        let requests = env.transport.requests.count
        let trigger = model.loadTrigger

        model.applyFavoriteChanges(Dictionary(uniqueKeysWithValues: model.entries.map { ($0.id, .removed) }))

        #expect(model.entries.isEmpty)
        #expect(model.loadTrigger != trigger)
        await model.loadIfNeeded()
        #expect(env.transport.requests.count == requests + 1)
    }

    @Test func whatLeavesAFolder() {
        #expect(GalleryListModel.leaves(3, by: .removed))
        #expect(GalleryListModel.leaves(-1, by: .removed))
        #expect(GalleryListModel.leaves(3, by: .added(folder: 4)))
        #expect(!GalleryListModel.leaves(3, by: .added(folder: 3)))
        #expect(!GalleryListModel.leaves(-1, by: .added(folder: 4)))
    }
}
