@testable import EhFeatures
import EhModels
import Testing

@Suite struct SearchTokensTests {
    @Test func exactTagTermsBecomeTokens() throws {
        let split = SearchTokens.split(#"f:"big breasts$" glasses artist:glacier$ -male:yaoi$ "a title""#)
        #expect(split.tokens.map(\.term) == [#"f:"big breasts$""#, "artist:glacier$", "-male:yaoi$"])
        #expect(split.remainder == #"glasses "a title""#)

        let first = try #require(split.tokens.first)
        #expect(first.namespace == "f")
        #expect(first.tag == "big breasts")
        #expect(!first.isExcluded)
        #expect(split.tokens[2].isExcluded)
        #expect(split.tokens[2].tag == "yaoi")
    }

    @Test func aTagWithoutANamespaceIsAToken() throws {
        let token = try #require(SearchToken(term: "glasses$"))
        #expect(token.namespace == nil)
        #expect(token.tag == "glasses")
        #expect(SearchToken(term: #""twin tails$""#)?.tag == "twin tails")
    }

    @Test func otherTermsStayText() {
        for term in [
            "glasses", "f:glasses", "$", "f:$", ":glasses$", #"f:"glasses""#, #""unterminated$"#,
            "f:glas$ses$", #"f:"""#, "uploader:someone"
        ] {
            #expect(SearchToken(term: term) == nil, "\(term)")
        }
    }

    @Test func joiningPutsTheTokensFirst() {
        let split = SearchTokens.split("glasses f:maid$")
        #expect(split.keyword == "f:maid$ glasses")
        #expect(SearchTokens().keyword.isEmpty)
        #expect(SearchTokens(tokens: [], remainder: "text").keyword == "text")
    }

    @Test func splittingAndJoiningRoundTrip() {
        let keywords = [
            "", "glasses", "f:glasses$", #"f:"big breasts$" artist:glacier$ some words"#,
            #"-male:yaoi$ "quoted title" plain"#, "f:maid$ f:maid$ text"
        ]
        for keyword in keywords {
            let split = SearchTokens.split(keyword)
            #expect(split.keyword == keyword, "\(keyword)")
            #expect(SearchTokens.split(split.keyword) == split, "\(keyword)")
        }
    }

    @Test func runsOfSpacesSeparateTerms() {
        let split = SearchTokens.split("  f:maid$   two  words ")
        #expect(split.tokens.map(\.term) == ["f:maid$"])
        #expect(split.remainder == "two words")
    }
}

@Suite struct SearchLooseningTests {
    private func filter(_ configure: (inout Filter) -> Void = { _ in }) -> Filter {
        var filter = Filter()
        configure(&filter)
        return filter
    }

    @Test func theDefaultFilterAndNoTagOfferNothing() {
        #expect(SearchLoosening.actions(for: "plain words", filter: filter()).isEmpty)
    }

    @Test func everyWayInOrder() throws {
        let narrow = filter {
            $0.advanced = true
            $0.minRatingActivated = true
            $0.minRating = 4
            $0.manga = true
            $0.misc = true
        }
        let actions = SearchLoosening.actions(for: "artist:glacier$ female:maid$ words", filter: narrow)
        let maid = try #require(SearchToken(term: "female:maid$"))
        #expect(actions == [.dropMinimumRating(4), .includeAllCategories, .dropTag(maid)])
    }

    /// The minimum rating counts only with advanced search on, as the site applies it.
    @Test func aRatingOutsideAdvancedSearchIsNotOffered() {
        let filter = filter { $0.minRatingActivated = true; $0.minRating = 4 }
        #expect(SearchLoosening.actions(for: "", filter: filter).isEmpty)
    }

    /// Excluding every category is no category filter.
    @Test func everyCategoryExcludedIsNotOffered() {
        let filter = filter {
            $0.doujinshi = true; $0.manga = true; $0.artistCG = true; $0.gameCG = true; $0.western = true
            $0.nonH = true; $0.imageSet = true; $0.cosplay = true; $0.asianPorn = true; $0.misc = true
        }
        #expect(SearchLoosening.actions(for: "", filter: filter).isEmpty)
    }

    @Test func applyingLoosensOnlyThatPart() throws {
        let narrow = filter {
            $0.advanced = true
            $0.minRatingActivated = true
            $0.minRating = 4
            $0.manga = true
        }
        let keyword = "artist:glacier$ words female:maid$"

        let rating = SearchLoosening.dropMinimumRating(4).applied(to: keyword, filter: narrow)
        #expect(rating.keyword == keyword)
        #expect(!rating.filter.minRatingActivated)
        #expect(rating.filter.manga)

        let categories = SearchLoosening.includeAllCategories.applied(to: keyword, filter: narrow)
        #expect(FilterSummary(categories.filter).categoriesShown == 10)
        #expect(categories.filter.minRatingActivated)

        let maid = try #require(SearchToken(term: "female:maid$"))
        let tag = SearchLoosening.dropTag(maid).applied(to: keyword, filter: narrow)
        #expect(tag.keyword == "artist:glacier$ words")
        #expect(tag.filter == narrow)
    }
}
