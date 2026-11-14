import EhModels
import Foundation
import Testing

@Suite struct FilterSummaryTests {
    @Test func theDefaultFilterNarrowsNothing() {
        let summary = FilterSummary(Filter())
        #expect(summary.categoriesShown == 10)
        #expect(summary.minimumRating == nil)
        #expect(summary.minimumPages == nil && summary.maximumPages == nil)
        #expect(summary.advancedOptionCount == 0)
        #expect(summary.isDefault)
    }

    @Test func excludedCategoriesAreNotShown() {
        var filter = Filter()
        filter.doujinshi = true
        filter.misc = true
        let summary = FilterSummary(filter)
        #expect(summary.categoriesShown == 8)
        #expect(!summary.isDefault)
    }

    /// The site treats excluding every category as no category filter.
    @Test func excludingEveryCategoryShowsThemAll() {
        var filter = Filter()
        for keyPath: WritableKeyPath<Filter, Bool> in [
            \.doujinshi, \.manga, \.artistCG, \.gameCG, \.western,
            \.nonH, \.imageSet, \.cosplay, \.asianPorn, \.misc
        ] {
            filter[keyPath: keyPath] = true
        }
        #expect(FilterSummary(filter).categoriesShown == 10)
        #expect(FilterSummary(filter).isDefault)
    }

    @Test func advancedOptionsCountOnlyWhileAdvancedSearchIsOn() {
        var filter = Filter()
        filter.minRatingActivated = true
        filter.minRating = 3
        filter.pageRangeActivated = true
        filter.pageLowerBound = "20"
        filter.galleryDesc = true
        #expect(FilterSummary(filter).isDefault)

        filter.advanced = true
        let summary = FilterSummary(filter)
        #expect(summary.minimumRating == 3)
        #expect(summary.minimumPages == 20 && summary.maximumPages == nil)
        #expect(summary.advancedOptionCount == 1)
        #expect(!summary.isDefault)
    }

    @Test func advancedSearchWithItsDefaultsNarrowsNothing() {
        var filter = Filter()
        filter.advanced = true
        #expect(FilterSummary(filter).isDefault)
    }

    @Test func optionsDifferingFromTheirDefaultsAreCounted() {
        var filter = Filter()
        filter.advanced = true
        filter.galleryName = false
        filter.onlyWithTorrents = true
        filter.lowPowerTags = true
        filter.expungedGalleries = true
        filter.disableLanguage = true
        filter.disableUploader = true
        filter.disableTags = true
        #expect(FilterSummary(filter).advancedOptionCount == 7)
    }

    @Test(arguments: [
        (2, true, 2), (5, true, 5), (3, false, nil), (1, true, nil), (6, true, nil)
    ] as [(Int, Bool, Int?)])
    func minimumRating(rating: Int, isActivated: Bool, expected: Int?) {
        var filter = Filter()
        filter.advanced = true
        filter.minRatingActivated = isActivated
        filter.minRating = rating
        #expect(FilterSummary(filter).minimumRating == expected)
    }

    @Test(arguments: [
        ("10", "50", 10, 50), ("10", "", 10, nil), ("", "50", nil, 50), ("50", "10", nil, nil),
        ("0", "", nil, nil), ("abc", "", nil, nil), ("", "", nil, nil)
    ] as [(String, String, Int?, Int?)])
    func pageRange(lower: String, upper: String, minimum: Int?, maximum: Int?) {
        var filter = Filter()
        filter.advanced = true
        filter.pageRangeActivated = true
        filter.pageLowerBound = lower
        filter.pageUpperBound = upper
        let summary = FilterSummary(filter)
        #expect(summary.minimumPages == minimum)
        #expect(summary.maximumPages == maximum)
        #expect(summary.isDefault == (minimum == nil && maximum == nil))
    }
}
