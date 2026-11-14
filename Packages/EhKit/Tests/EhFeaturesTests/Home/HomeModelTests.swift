import Dependencies
import EhCore
@testable import EhFeatures
import EhModels
import EhNetworking
import EhTestSupport
import Foundation
import Synchronization
import Testing

@Suite struct HomeModelTests {
    private let transport = StubTransport()

    // MARK: Loading

    @Test func loadsPopularAsEntries() async throws {
        transport.on(.any, reply: .fixture("Parser/List/PopularCompactList.html"))
        let model = makeModel()
        #expect(model.loadingState == .idle)

        await model.refresh()

        #expect(model.loadingState == .idle)
        #expect(model.entries.count == 100)
        #expect(transport.requests.map { $0.url?.path() } == ["/popular"])
        // Each entry carries its parsed title.
        let entry = try #require(model.entries.first { $0.title.isParsed })
        #expect(entry.title == TitleParser.parse(entry.gallery.title))
    }

    @Test func entriesCarryTheFavouriteMarksOfThePage() async throws {
        let html = try Fixture.string("Parser/List/FrontPageCompactList.html").replacingOccurrences(
            of: #"id="posted_2668616""#, with: #"style="border-color:#f00" id="posted_2668616""#
        )
        transport.on(.any, reply: .html(html))
        let model = makeModel()

        await model.refresh()

        #expect(model.entries.first { $0.id == "2668616" }?.favorite == FavoriteMark(folder: 1))
        #expect(model.entries.filter { $0.favorite != nil }.count == 1)
    }

    @Test func popularUsesTheGlobalFilter() async throws {
        transport.on(.any, reply: .fixture("Parser/List/PopularCompactList.html"))
        let filters = FilterStore(defaults: UserDefaults(suiteName: "HomeTests-\(UUID().uuidString)")!)
        filters.globalFilter.doujinshi = true
        let model = makeModel(filters: filters)

        await model.refresh()

        let query = transport.requests.first?.url?.query() ?? ""
        #expect(query.contains("f_cats"))
    }

    @Test func emptyPopularIsNotFound() async throws {
        transport.on(.any, reply: .html("<html><body></body></html>"))
        let model = makeModel()

        await model.refresh()

        #expect(model.loadingState == .failed(.notFound))
        #expect(model.entries.isEmpty)
    }

    @Test func exhentaiRefusingTheSessionFailsWithThatReason() async throws {
        transport.on(.any, reply: .status(200))
        let model = makeModel(host: .exhentai)

        await model.refresh()

        #expect(model.loadingState == .failed(.exhentaiAccessDenied))
    }

    // MARK: Reload

    @Test func aFailedReloadKeepsWhatIsShown() async throws {
        transport.on(.any, replies: .fixture("Parser/List/PopularCompactList.html"), .error(URLError(.timedOut)))
        let model = makeModel()
        await model.refresh()
        let entries = model.entries

        await model.refresh()

        #expect(transport.requests.count == 2)
        #expect(model.loadingState == .failed(.networkingFailed))
        #expect(model.entries == entries)
    }

    @Test func reloadingWhileLoadingWaitsForTheSameLoad() async throws {
        let gate = Gate()
        transport.on(.any, reply: .handler { request in
            await gate.wait()
            return try Fixture.response("Parser/List/PopularCompactList.html", for: request)
        })
        let model = makeModel()
        model.loadIfNeeded()
        #expect(model.loadingState == .loading)

        model.reload()
        model.loadIfNeeded()
        let refresh = Task { await model.refresh() }
        gate.open()
        await refresh.value

        #expect(transport.requests.count == 1)
        #expect(!model.entries.isEmpty)
    }

    @Test func appearingAgainLoadsOnlyWhenNothingIsShown() async throws {
        transport.on(.any, replies: .error(URLError(.notConnectedToInternet)), .fixture("Parser/List/PopularCompactList.html"))
        let model = makeModel()
        await model.refresh()
        #expect(model.loadingState == .failed(.networkingFailed))

        model.loadIfNeeded()
        await model.refresh()
        #expect(!model.entries.isEmpty)
        let count = transport.requests.count

        model.loadIfNeeded()
        #expect(model.loadingState == .idle)
        #expect(transport.requests.count == count)
    }

    // MARK: Leaving the screen

    @Test func releasingTheModelCancelsTheLoadWithoutFailing() async throws {
        let cancelled = Mutex(false)
        let started = Gate()
        transport.on(.any, reply: .handler { _ in
            started.open()
            do {
                while true { try await Task.sleep(for: .seconds(3600)) }
            } catch {
                cancelled.withLock { $0 = true }
                throw URLError(.cancelled)
            }
        })
        var model: HomeModel? = makeModel()
        model?.loadIfNeeded()
        await started.wait()
        weak let released = model

        model = nil

        #expect(released == nil)
        while !cancelled.withLock({ $0 }) { try await Task.sleep(for: .milliseconds(5)) }
    }

    // MARK: Helpers

    private func makeModel(host: GalleryHost = .ehentai, filters: FilterStore? = nil) -> HomeModel {
        let client = EhClient(
            transport: transport, cookies: CookieStore(storage: InMemoryCookieStorage()), host: { host }
        )
        return withDependencies {
            $0.ehClient = client
            if let filters { $0.filterStore = filters }
        } operation: {
            HomeModel()
        }
    }
}
