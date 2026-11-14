import Dependencies
import EhCore
import EhModels
import EhNetworking
import Foundation
import Observation

/// The search surface every search design draws: the field's tokens and text, the scope, tag
/// suggestions, quick searches, recent searches and recently seen galleries, and the offer to
/// open a link on the clipboard.
///
/// It joins what already exists: `root` keeps the quick-search words, the search history and
/// the recently seen galleries current; `suggestions` ranks tags for the text being typed.
///
/// **Driving it from a view.** `.task { await model.observe() }` keeps the lists current;
/// `.task { await model.checkForLink() }` when the surface appears looks for a link.
@Observable
public final class SearchSurfaceModel {
    /// Where results go: Everywhere is the site's search, the others search a list.
    public var scope: SearchScope
    /// The accepted tags, shown as tokens before the text.
    public private(set) var tokens: [SearchToken] = []
    /// What is typed after the tokens.
    public var text = "" {
        didSet {
            if text != oldValue { suggestions.textDidChange(TagSuggestionModel.normalize(text)) }
        }
    }
    /// Whether the clipboard probably holds a link and "Detects links from clipboard" is on.
    /// The link itself is read only by `openLink()`, so no paste prompt shows before a tap.
    public private(set) var hasLinkOffer = false

    /// Quick-search words, the search history and the recently seen galleries.
    public let root: SearchRootModel
    /// Tag suggestions for `text`.
    public let suggestions: TagSuggestionModel

    @ObservationIgnored @Dependency(\.settings) private var settings
    @ObservationIgnored @Dependency(\.clipboardClient) private var clipboard
    @ObservationIgnored @Dependency(\.cookieStore) private var cookieStore
    @ObservationIgnored @Dependency(\.database) private var database

    /// Cheap: nothing is read until `observe()`.
    public init(scope: SearchScope = .everywhere) {
        self.scope = scope
        root = SearchRootModel()
        suggestions = TagSuggestionModel()
    }

    // MARK: Derived

    /// The keyword the field holds: the tokens' terms, then the text.
    public var keyword: String {
        SearchTokens(tokens: tokens, remainder: text.trimmingCharacters(in: .whitespaces)).keyword
    }

    public var isEmpty: Bool { tokens.isEmpty && text.trimmingCharacters(in: .whitespaces).isEmpty }

    /// Favourites and Watched need a signed-in user; signed out they are dimmed.
    public func isAvailable(_ scope: SearchScope) -> Bool {
        scope == .everywhere || cookieStore.didLogin
    }

    /// Quick searches whose keyword or name contains the text ("Saved" while typing); all of
    /// them before anything is typed.
    public var matchingQuickSearches: [SearchKeyword] {
        let text = text.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return root.quickSearchKeywords }
        return root.quickSearchKeywords.filter {
            $0.keyword.localizedCaseInsensitiveContains(text) || $0.title.localizedCaseInsensitiveContains(text)
        }
    }

    // MARK: Lifecycle

    /// Keeps the quick searches, recent searches and recently seen galleries current until the
    /// calling task is cancelled.
    public func observe() async {
        await root.observe()
    }

    /// Stops the suggestion lookup in flight, e.g. when the surface goes away.
    public func cancel() {
        suggestions.cancel()
    }

    // MARK: Editing

    /// A tag suggestion was chosen: the fragment it matched becomes its token.
    public func accept(_ suggestion: SearchTagSuggestion) {
        let completed = TagSuggestionModel.complete(text, with: suggestion.suggestion)
        let split = SearchTokens.split(completed)
        appendTokens(split.tokens)
        text = split.remainder
    }

    public func removeToken(_ token: SearchToken) {
        tokens.removeAll { $0 == token }
    }

    /// The backspace at the start of the text.
    public func removeLastToken() {
        if !tokens.isEmpty { tokens.removeLast() }
    }

    /// Fills the field with `keyword` (a recent search, a quick search), its tags as tokens.
    public func use(_ keyword: String) {
        let split = SearchTokens.split(TagSuggestionModel.normalize(keyword))
        tokens = []
        appendTokens(split.tokens)
        text = split.remainder
    }

    public func clear() {
        tokens = []
        text = ""
    }

    private func appendTokens(_ new: [SearchToken]) {
        for token in new where !tokens.contains(token) {
            tokens.append(token)
        }
    }

    // MARK: Submitting

    /// Pushes the results of the field's keyword in the current scope.
    public func submit(on stack: StackRouter) {
        search(keyword, on: stack)
    }

    /// Pushes the results of `keyword` in the current scope.
    public func search(_ keyword: String, on stack: StackRouter) {
        stack.push(Self.route(for: keyword, in: scope))
    }

    /// Everywhere is the site's search, which records the search history; Favourites and
    /// Watched search their list.
    nonisolated public static func route(for keyword: String, in scope: SearchScope) -> Route {
        switch scope {
        case .everywhere: .typedSearch(keyword: keyword)
        case .favorites, .watched: .listSearch(scope, keyword: keyword)
        }
    }

    public func clearRecentSearches() async {
        try? await database.clearSearchHistory()
    }

    public func removeRecentSearch(_ keyword: String) async {
        await root.removeHistoryKeyword(keyword)
    }

    // MARK: Copied link

    /// Looks for a link on the clipboard, by pattern only, when the setting allows it.
    public func checkForLink() async {
        let found = settings.detectsLinksFromClipboard ? await clipboard.hasProbableURL() : false
        if hasLinkOffer != found { hasLinkOffer = found }
    }

    /// "Open": reads the link (the system may ask to paste) and withdraws the offer. The caller
    /// opens it as any gallery link.
    public func openLink() -> URL? {
        hasLinkOffer = false
        return clipboard.url()
    }
}
