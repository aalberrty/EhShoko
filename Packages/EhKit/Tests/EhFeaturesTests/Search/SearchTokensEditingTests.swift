@testable import EhFeatures
import Testing

/// The search field's text rules (`SearchTokens+Editing.swift`).
@Suite struct SearchTokensEditingTests {
    @Test func theLookupDropsTheLastWordsMarkOnly() {
        #expect(SearchTokens.lookupText(beforeCaret: "summer -gla") == "summer gla")
        #expect(SearchTokens.lookupText(beforeCaret: "~kimo") == "kimo")
        #expect(SearchTokens.lookupText(beforeCaret: "-maid gla") == "-maid gla")
        #expect(SearchTokens.lookupText(beforeCaret: "a-b") == "a-b")
        #expect(SearchTokens.lookupText(beforeCaret: "") == "")
        #expect(SearchTokens.lookupText(beforeCaret: "words ") == "words ")
    }

    @Test func aNamespaceKeyAfterAWordGetsASpace() {
        #expect(SearchTokens.needsSpace(beforeKey: "artist:", after: "r"))
        #expect(!SearchTokens.needsSpace(beforeKey: "artist:", after: " "))
        #expect(!SearchTokens.needsSpace(beforeKey: "artist:", after: "-"))
        #expect(!SearchTokens.needsSpace(beforeKey: "artist:", after: "~"))
        #expect(!SearchTokens.needsSpace(beforeKey: "artist:", after: nil))
        // `-` and `$` go in as they are.
        #expect(!SearchTokens.needsSpace(beforeKey: "-", after: "r"))
        #expect(!SearchTokens.needsSpace(beforeKey: "$", after: "r"))
    }

    @Test func aSpaceAfterACompleteTermCompletesIt() {
        #expect(SearchTokens.completedTerm(beforeCaret: "summer f:kimono$ ") == "f:kimono$")
        #expect(SearchTokens.completedTerm(beforeCaret: "-l:chinese$ ") == "-l:chinese$")
        #expect(SearchTokens.completedTerm(beforeCaret: #"a f:"big breasts$" "#) == #"f:"big breasts$""#)
        // Not yet: no space typed, an incomplete term, a space inside an open quote.
        #expect(SearchTokens.completedTerm(beforeCaret: "f:kimono$") == nil)
        #expect(SearchTokens.completedTerm(beforeCaret: "f:kimo ") == nil)
        #expect(SearchTokens.completedTerm(beforeCaret: #"f:"big "#) == nil)
        #expect(SearchTokens.completedTerm(beforeCaret: "summer ") == nil)
    }

    @Test func aSuggestionReplacesTheFragmentAndKeepsItsMark() throws {
        let plain = try #require(SearchTokens.replacement(for: "gla", keyword: "f:glasses$", beforeCaret: "summer gla"))
        #expect(plain.length == 3)
        #expect(plain.term == "f:glasses$")

        let excluded = try #require(SearchTokens.replacement(for: "gla", keyword: "f:glasses$", beforeCaret: "summer -gla"))
        #expect(excluded.length == 4)
        #expect(excluded.term == "-f:glasses$")

        // Two words, typed with a double space the lookup collapsed, in another case.
        let words = try #require(
            SearchTokens.replacement(for: "big bre", keyword: #"f:"big breasts$""#, beforeCaret: "x Big  Bre")
        )
        #expect(words.length == 8)
        #expect(words.term == #"f:"big breasts$""#)
    }

    @Test func aSuggestionForTextThatIsGoneReplacesNothing() {
        #expect(SearchTokens.replacement(for: "gla", keyword: "f:glasses$", beforeCaret: "summer") == nil)
        #expect(SearchTokens.replacement(for: "", keyword: "f:glasses$", beforeCaret: "summer") == nil)
    }
}
