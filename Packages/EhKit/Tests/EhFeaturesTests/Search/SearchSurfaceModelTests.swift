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
    let clipboardURL = LockIsolated(URL(string: "https://e-hentai.org/g/1/abc/"))
    /// The texts suggestions were looked up for.
    let lookups = LockIsolated<[String]>([])

    init() throws {
        database = try AppDatabase.makeInMemory()
    }

    private func makeModel(scope: SearchScope = .everywhere) -> SearchSurfaceModel {
        withDependencies {
            $0.settings = settings
            $0.cookieStore = cookies
            $0.database = database
            $0.continuousClock = NoWaitClock()
            $0.tagSuggestionSource = TagSuggestionSource(
                hasTranslations: { true },
                suggestions: { [lookups] text, _ in
                    lookups.withValue { $0.append(text) }
                    return TagSuggestionResults(items: [Self.suggestion(for: text)], matchCount: 1)
                }
            )
            $0.clipboardClient = ClipboardClient(
                changeCount: { 0 },
                url: { [urlReads, clipboardURL] in
                    urlReads.withValue { $0 += 1 }
                    return clipboardURL.value
                },
                copyText: { _ in }, copyImage: { _ in },
                hasProbableURL: { [hasProbableURL] in hasProbableURL.value }
            )
        } operation: {
            SearchSurfaceModel(scope: scope)
        }
    }

    nonisolated private static func suggestion(for text: String) -> SearchTagSuggestion {
        SearchTagSuggestion(
            suggestion: TagSuggestion(
                tag: TagTranslation(namespace: .female, key: text, value: text), weight: 1,
                keyRange: nil, valueRange: nil, originalKeyword: text, matchesNamespace: false
            ),
            displayValue: text, imageURL: nil
        )
    }

    private func enableSuggestions() {
        settings.enablesTagsExtension = true
        settings.showsTagsSearchSuggestion = true
    }

    private func edit(_ terms: [String], _ text: String, beforeCaret: String? = nil) -> TagSearchFieldEdit {
        TagSearchFieldEdit(tokens: terms.compactMap(SearchToken.init(term:)), text: text, beforeCaret: beforeCaret ?? text)
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
        model.replaceKeyword("glasses f:maid$")
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

    // MARK: The field and the model

    @Test func aKeywordHandedInFillsTokensAndTextAndBumpsTheRevision() {
        let model = makeModel()
        #expect(model.isEmpty)
        #expect(model.revision == 0)
        model.replaceKeyword(#"artist:glacier$  some  title f:"big breasts$" artist:glacier$"#)
        #expect(model.tokens.map(\.term) == ["artist:glacier$", #"f:"big breasts$""#])
        #expect(model.text == "some title")
        #expect(model.keyword == #"artist:glacier$ f:"big breasts$" some title"#)
        #expect(model.revision == 1)

        model.replaceKeyword("")
        #expect(model.isEmpty)
        #expect(model.keyword.isEmpty)
        #expect(model.revision == 2)
    }

    @Test func theFieldsEditsAreTakenAsTheyAreWithoutARevision() {
        let model = makeModel()
        model.fieldDidEdit(edit(["f:maid$", "-m:yaoi$"], "words  glas"))
        #expect(model.tokens.map(\.term) == ["f:maid$", "-m:yaoi$"])
        // The field's own text, not normalised: the field keeps the site's syntax as typed.
        #expect(model.text == "words  glas")
        #expect(model.keyword == "f:maid$ -m:yaoi$ words  glas")

        // A token deleted in the field.
        model.fieldDidEdit(edit(["-m:yaoi$"], "words glas"))
        #expect(model.tokens.map(\.term) == ["-m:yaoi$"])
        #expect(model.revision == 0)
    }

    @Test func suggestionsAreLookedUpForTheTextBeforeTheCaretWithoutItsMark() async throws {
        enableSuggestions()
        let model = makeModel()

        model.fieldDidEdit(edit([], "summer  -gla tail", beforeCaret: "summer  -gla"))

        try await eventually { !model.suggestions.suggestions.isEmpty }
        #expect(lookups.value == ["summer gla"])
        #expect(model.suggestions.suggestions.map(\.suggestion.tag.key) == ["summer gla"])
    }

    @Test func aTakenTokenClearsTheSuggestionsAtOnce() async throws {
        enableSuggestions()
        let model = makeModel()
        model.fieldDidEdit(edit([], "glas"))
        try await eventually { !model.suggestions.suggestions.isEmpty }

        // The field turned "glas" into a token; the list for "glas" goes before any lookup.
        model.fieldDidEdit(edit(["f:glasses$"], ""))
        #expect(model.suggestions.suggestions.isEmpty)
        #expect(model.tokens.map(\.term) == ["f:glasses$"])
    }

    @Test func aKeywordHandedInShowsNoSuggestions() async throws {
        enableSuggestions()
        let model = makeModel()
        model.fieldDidEdit(edit([], "glas"))
        try await eventually { !model.suggestions.suggestions.isEmpty }

        model.replaceKeyword("glasses")
        #expect(model.suggestions.suggestions.isEmpty)
    }

    @Test func savedSearchesMatchTheText() async throws {
        try await database.insertQuickSearchWord(QuickSearchWord(name: "Glasses", content: "f:glasses$"))
        try await database.insertQuickSearchWord(QuickSearchWord(name: "Maids", content: "f:maid$"))
        let model = makeModel()
        let observing = Task { await model.observe() }
        defer { observing.cancel() }
        await waitUntil { model.root.quickSearchWords.count == 2 }

        #expect(model.matchingQuickSearches.map(\.title) == ["Glasses", "Maids"])
        model.fieldDidEdit(edit([], "GLASS "))
        #expect(model.matchingQuickSearches.map(\.title) == ["Glasses"])
        model.fieldDidEdit(edit([], "nothing"))
        #expect(model.matchingQuickSearches.isEmpty)
    }

    @Test func recentSearchesMatchTheText() async throws {
        try await database.recordSearchKeywords(["summer glasses", "kimono", "Glasses girl"])
        let model = makeModel()
        let observing = Task { await model.observe() }
        defer { observing.cancel() }
        await waitUntil { model.root.historyKeywords.count == 3 }
        let all = model.root.historyKeywords

        #expect(model.matchingRecentSearches == all)
        model.fieldDidEdit(edit(["f:maid$"], " glass"))
        #expect(model.matchingRecentSearches == all.filter { $0 != "kimono" })
        model.fieldDidEdit(edit([], "nothing"))
        #expect(model.matchingRecentSearches.isEmpty)
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

        // As the app's own link, which the shell opens as a shared one.
        #expect(model.openLink() == URL(string: "ehshoko://e-hentai.org/g/1/abc/"))
        #expect(urlReads.value == 1)
        #expect(!model.hasLinkOffer)
    }

    @Test func aLinkThatIsNotAGalleryOpensNothing() async {
        settings.detectsLinksFromClipboard = true
        hasProbableURL.setValue(true)
        clipboardURL.setValue(URL(string: "https://example.com/g/1/abc/"))
        let model = makeModel()
        await model.checkForLink()

        #expect(model.openLink() == nil)
        #expect(!model.hasLinkOffer)
    }

    @Test func clearingRecentSearches() async throws {
        try await database.recordSearchKeywords(["one", "two"])
        let model = makeModel()
        await model.clearRecentSearches()
        #expect(try await storedHistory(database).isEmpty)
    }
}
