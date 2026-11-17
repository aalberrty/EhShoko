import Dependencies
import EhCore
@testable import EhFeatures
import EhModels
import EhNetworking
import EhTestSupport
import Foundation
import os
import Testing

/// The loads whose signposts mark the response's arrival run their requests where the client
/// can tell them: with `ResponseArrival.observer` bound. (What the observer records is a
/// signpost, which a test cannot read; `PerformanceSignpostsTests` covers that half.)
@MainActor
@Suite struct ResponseMarkingTests {
    /// Answers every request with `fixture` and notes whether an observer was bound when it
    /// was asked.
    private func observe(_ transport: StubTransport, fixture: String) -> OSAllocatedUnfairLock<[Bool]> {
        let bound = OSAllocatedUnfairLock<[Bool]>(initialState: [])
        transport.on(.any, reply: .handler { request in
            bound.withLock { $0.append(ResponseArrival.observer != nil) }
            return try Fixture.response(fixture, for: request)
        })
        return bound
    }

    @Test func popularOnTheFirstScreen() async throws {
        let transport = StubTransport()
        let bound = observe(transport, fixture: "Parser/List/PopularCompactList.html")
        let client = EhClient(
            transport: transport, cookies: CookieStore(storage: InMemoryCookieStorage()), host: { .ehentai }
        )
        let model = withDependencies { $0.ehClient = client } operation: { HomeModel() }

        await model.refresh()

        #expect(!model.entries.isEmpty)
        #expect(bound.withLock { $0 } == [true])
    }

    @Test func aListsFirstAndNextPage() async throws {
        let env = try ListTestEnvironment()
        let bound = observe(env.transport, fixture: ListFixture.frontpage)
        let model = env.make { GalleryListModel(source: .frontpage) }

        await model.loadIfNeeded()
        await model.loadMore()

        #expect(env.transport.requests.count == 2)
        #expect(bound.withLock { $0 } == [true, true])
    }

    @Test func aGalleryPagesFetch() async throws {
        let env = try await DetailEnvironment()
        let bound = observe(env.transport, fixture: "Parser/Gallery/GalleryDetail.html")
        let model = env.makeDetailModel()

        await model.load()

        #expect(model.loadingState == .idle)
        #expect(bound.withLock { $0 } == [true])
    }
}
