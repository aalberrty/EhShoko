import Dependencies
import EhCore
import EhDatabase
@testable import EhFeatures
import EhModels
import EhNetworking
import EhTestSupport
import Foundation
import Testing

@MainActor
@Suite struct SearchSurfaceModelTests {
    let settings = SettingsStore(defaults: UserDefaults(suiteName: "F5Tests-\(UUID().uuidString)")!)
    let cookies = CookieStore(storage: InMemoryCookieStorage())
    let database: AppDatabase
    /// What the clipboard's pattern detection answers, and how often the URL was read.
    let hasProbableURL = LockIsolated(false)
    let urlReads = LockIsolated(0)

    init() throws {
        database = try AppDatabase.makeInMemory()
    }

    private func makeModel(scope: SearchScope = .everywhere) -> SearchSurfaceModel {
        withDependencies {
            $0.settings = settings
            $0.cookieStore = cookies
            $0.database = database
            $0.continuousClock = NoWaitClock()
            $0.clipboardClient = ClipboardClient(
                changeCount: { 0 },
                url: { [urlReads] in
                    urlReads.withValue { $0 += 1 }
                    return URL(string: "https://e-hentai.org/g/1/abc/")
                },
                copyText: { _ in }, copyImage: { _ in },
                hasProbableURL: { [hasProbableURL] in hasProbableURL.value }
            )
        } operation: {
            SearchSurfaceModel(scope: scope)
        }
    }

    private func logIn() {
        cookies.setOrEditCookie(for: GalleryHost.ehentai.url, name: CookieName.ipbMemberId, value: "1")
        cookies.setOrEditCookie(for: GalleryHost.ehentai.url, name: CookieName.ipbPassHash, value: "hash")
    }

    // MARK: Scopes

    @Test func everywhereIsTheSitesSearchAndTheOthersSearchTheirList() {
        #expect(SearchSurfaceModel.route(for: "maid", in: .everywhere) == .typedSearch(keyword: "maid"))
        #expect(SearchSurfaceModel.route(for: "maid", in: .favorites) == .listSearch(.favorites, keyword: "maid"))
        #expect(SearchSurfaceModel.route(for: "maid", in: .watched) == .listSearch(.watched, keyword: "maid"))
    }

    @Test func submitPushesTheFieldsKeywordInTheScope() {
        let model = makeModel(scope: .watched)
        #expect(model.scope == .watched)
        let stack = StackRouter()
        model.use("glasses f:maid$")
        model.submit(on: stack)
        #expect(stack.path == [.listSearch(.watched, keyword: "f:maid$ glasses")])

        model.scope = .everywhere
        model.search("other", on: stack)
        #expect(stack.path.last == .typedSearch(keyword: "other"))
    }

    @Test func favouritesAndWatchedNeedASignIn() {
        let model = makeModel()
        #expect(model.isAvailable(.everywhere))
        #expect(!model.isAvailable(.favorites))
        #expect(!model.isAvailable(.watched))
        logIn()
        #expect(SearchScope.allCases.allSatisfy(model.isAvailable))
    }

    // MARK: Tokens

    @Test func aRecentSearchFillsTokensAndText() {
        let model = makeModel()
        #expect(model.isEmpty)
        model.use(#"artist:glacier$  some  title f:"big breasts$""#)
        #expect(model.tokens.map(\.term) == ["artist:glacier$", #"f:"big breasts$""#])
        #expect(model.text == "some title")
        #expect(model.keyword == #"artist:glacier$ f:"big breasts$" some title"#)

        model.removeLastToken()
        #expect(model.tokens.map(\.term) == ["artist:glacier$"])
        model.removeToken(model.tokens[0])
        #expect(model.tokens.isEmpty)
        model.clear()
        #expect(model.isEmpty)
        #expect(model.keyword.isEmpty)
    }

    @Test func aChosenSuggestionBecomesAToken() {
        let model = makeModel()
        model.use("f:maid$")
        model.text = "words glas"
        let suggestion = SearchTagSuggestion(
            suggestion: TagSuggestion(
                tag: TagTranslation(namespace: .female, key: "glasses", value: "眼镜"), weight: 1,
                keyRange: nil, valueRange: nil, originalKeyword: "glas", matchesNamespace: false
            ),
            displayValue: "眼镜", imageURL: nil
        )
        model.accept(suggestion)
        #expect(model.tokens.map(\.term) == ["f:maid$", "f:glasses$"])
        #expect(model.text == "words")

        // Choosing it again does not repeat the token.
        model.text = "glas"
        model.accept(suggestion)
        #expect(model.tokens.map(\.term) == ["f:maid$", "f:glasses$"])
        #expect(model.text.isEmpty)
    }

    @Test func savedSearchesMatchTheText() async throws {
        try await database.insertQuickSearchWord(QuickSearchWord(name: "Glasses", content: "f:glasses$"))
        try await database.insertQuickSearchWord(QuickSearchWord(name: "Maids", content: "f:maid$"))
        let model = makeModel()
        let observing = Task { await model.observe() }
        defer { observing.cancel() }
        await waitUntil { model.root.quickSearchWords.count == 2 }

        #expect(model.matchingQuickSearches.map(\.title) == ["Glasses", "Maids"])
        model.text = "GLASS"
        #expect(model.matchingQuickSearches.map(\.title) == ["Glasses"])
        model.text = "nothing"
        #expect(model.matchingQuickSearches.isEmpty)
    }

    // MARK: Copied link

    @Test func theLinkOfferNeedsThePatternAndTheSetting() async {
        let model = makeModel()
        hasProbableURL.setValue(true)
        await model.checkForLink()
        #expect(!model.hasLinkOffer, "the setting is off")

        settings.detectsLinksFromClipboard = true
        hasProbableURL.setValue(false)
        await model.checkForLink()
        #expect(!model.hasLinkOffer, "no link on the clipboard")

        hasProbableURL.setValue(true)
        await model.checkForLink()
        #expect(model.hasLinkOffer)
        // Looking reads nothing, so no paste prompt shows.
        #expect(urlReads.value == 0)
    }

    @Test func openReadsTheLinkOnceAndWithdrawsTheOffer() async {
        settings.detectsLinksFromClipboard = true
        hasProbableURL.setValue(true)
        let model = makeModel()
        await model.checkForLink()

        #expect(model.openLink() == URL(string: "https://e-hentai.org/g/1/abc/"))
        #expect(urlReads.value == 1)
        #expect(!model.hasLinkOffer)
    }

    @Test func clearingRecentSearches() async throws {
        try await database.recordSearchKeywords(["one", "two"])
        let model = makeModel()
        await model.clearRecentSearches()
        #expect(try await storedHistory(database).isEmpty)
    }
}
