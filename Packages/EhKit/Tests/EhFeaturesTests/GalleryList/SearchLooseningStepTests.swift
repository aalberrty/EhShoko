import EhCore
import EhModels
import Foundation
import Testing
@testable import EhFeatures

@MainActor
@Suite struct SearchLooseningStepTests {
    private func store(_ configure: (inout Filter) -> Void) -> FilterStore {
        let store = FilterStore(defaults: UserDefaults(suiteName: "Loosening-\(UUID().uuidString)")!)
        var filter = Filter()
        configure(&filter)
        store[.search] = filter
        return store
    }

    private let keyword = "artist:glacier$ words female:maid$"

    @Test func droppingTheRatingLoosensTheSearchFilterAndReloads() {
        let filterStore = store { $0.advanced = true; $0.minRatingActivated = true; $0.minRating = 4; $0.manga = true }

        let step = SearchLoosening.dropMinimumRating(4).perform(on: keyword, filterStore: filterStore)

        #expect(step == .reload)
        #expect(!filterStore[.search].minRatingActivated)
        #expect(filterStore[.search].manga)
        // The other filters are not the empty search's.
        #expect(filterStore[.global] == Filter())
    }

    @Test func includingEveryCategoryLoosensTheSearchFilterAndReloads() {
        let filterStore = store { $0.manga = true; $0.misc = true }

        let step = SearchLoosening.includeAllCategories.perform(on: keyword, filterStore: filterStore)

        #expect(step == .reload)
        #expect(FilterSummary(filterStore[.search]).categoriesShown == FilterSummary.categoryCount)
    }

    @Test func droppingATagSearchesAgainAndLeavesTheFilter() throws {
        let filterStore = store { $0.manga = true }
        let maid = try #require(SearchToken(term: "female:maid$"))

        let step = SearchLoosening.dropTag(maid).perform(on: keyword, filterStore: filterStore)

        #expect(step == .search("artist:glacier$ words"))
        #expect(filterStore[.search].manga)
    }
}
