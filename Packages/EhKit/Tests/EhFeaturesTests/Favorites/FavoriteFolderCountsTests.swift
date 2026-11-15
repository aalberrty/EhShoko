@testable import EhFeatures
import EhModels
import EhTestSupport
import Foundation
import Testing

@Suite struct FavoriteFolderCountsTests {
    @Test func asksForAllFavouritesOnceWhileTheCountsAreUnknown() async throws {
        let env = try ListTestEnvironment()
        env.transport.on(.any, reply: .fixture(ListFixture.favorites))
        let counts = env.make { FavoriteFolderCounts() }

        await counts.loadIfUnknown()
        #expect(env.transport.requests.count == 1)
        #expect(env.query("favcat", ofRequest: 0) == "all")
        #expect(!env.userStore.favoriteFolderCounts.isEmpty)

        await counts.loadIfUnknown()
        #expect(env.transport.requests.count == 1)
    }

    @Test func asksNothingWhenAFavouritesPageBroughtTheCounts() async throws {
        let env = try ListTestEnvironment()
        env.userStore.updateFavoriteFolders([FavoriteFolder(index: 0, name: "Favorites 0", count: 3)])
        let counts = env.make { FavoriteFolderCounts() }

        await counts.loadIfUnknown()

        #expect(env.transport.requests.isEmpty)
    }

    /// The Index first shown signed out asked nothing then; once the user signs in on it, the
    /// same model asks.
    @Test func firstAskedSignedOutAsksAfterSigningIn() async throws {
        let env = try ListTestEnvironment(loggedIn: false)
        env.transport.on(.any, reply: .fixture(ListFixture.favorites))
        let counts = env.make { FavoriteFolderCounts() }

        await counts.loadIfUnknown()
        #expect(env.transport.requests.isEmpty)

        env.logIn()
        await counts.loadIfUnknown()
        #expect(env.transport.requests.count == 1)
        #expect(!env.userStore.favoriteFolderCounts.isEmpty)
    }

    @Test func aFailedRequestIsNotRepeatedInTheSameSignIn() async throws {
        let env = try ListTestEnvironment()
        env.transport.on(.any, reply: .error(URLError(.notConnectedToInternet)))
        let counts = env.make { FavoriteFolderCounts() }

        await counts.loadIfUnknown()
        await counts.loadIfUnknown()

        #expect(env.transport.requests.count == 1)
        #expect(env.userStore.favoriteFolderCounts.isEmpty)
    }

    /// Signing out forgets the counts (`UserStore.clear()`); the next sign-in asks again.
    @Test func asksAgainAfterSigningOutAndIn() async throws {
        let env = try ListTestEnvironment()
        env.transport.on(.any, reply: .fixture(ListFixture.favorites))
        let counts = env.make { FavoriteFolderCounts() }
        await counts.loadIfUnknown()

        env.userStore.clear()
        env.cookies.clearAll()
        await counts.loadIfUnknown()
        #expect(env.transport.requests.count == 1)

        env.logIn()
        await counts.loadIfUnknown()
        #expect(env.transport.requests.count == 2)
    }

    @Test func refreshAsksEvenWhenTheCountsAreKnownButNotWhenSignedOut() async throws {
        let env = try ListTestEnvironment()
        env.transport.on(.any, reply: .fixture(ListFixture.favorites))
        let counts = env.make { FavoriteFolderCounts() }
        await counts.loadIfUnknown()

        await counts.refresh()
        #expect(env.transport.requests.count == 2)

        env.cookies.clearAll()
        await counts.refresh()
        #expect(env.transport.requests.count == 2)
    }
}
