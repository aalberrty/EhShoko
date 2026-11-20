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
///
/// **The field leads; the model follows** (`spikes/S6.md` section 11). Every edit the field
/// makes is reported with `fieldDidEdit(_:)`, and nothing is written back to the field on a
/// keystroke. Content goes the other way only through `replaceKeyword(_:)`, which bumps
/// `revision`: a field shows the model's content again when that changes.
@Observable
public final class SearchSurfaceModel {
    /// Where results go: Everywhere is the site's search, the others search a list.
    public var scope: SearchScope
    /// The accepted tags, shown as tokens before the text.
    public private(set) var tokens: [SearchToken] = []
    /// What is typed after the tokens. Read it in one small view only: it changes with every
    /// keystroke.
    public private(set) var text = ""
    /// Bumped each time the model replaces the field's content (`replaceKeyword(_:)`), and
    /// only then.
    public private(set) var revision = 0
    /// Whether the clipboard probably holds a link and "Detects links from clipboard" is on.
    /// The link itself is read only by `openLink()`, so no paste prompt shows before a tap.
    public private(set) var hasLinkOffer = false

    /// Quick-search words, the search history and the recently seen galleries.
    public let root: SearchRootModel
    /// Tag suggestions for the word at the caret.
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

    /// Recent searches that contain the text ("Recent" while typing), newest first; all of
    /// them before anything is typed.
    public var matchingRecentSearches: [String] {
        let text = text.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return root.historyKeywords }
        return root.historyKeywords.filter { $0.localizedCaseInsensitiveContains(text) }
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

    /// Every edit the field reports: its tokens and text become the model's, and suggestions
    /// are looked up for the text before the caret, without the last word's mark. Never
    /// writes back to the field.
    public func fieldDidEdit(_ edit: TagSearchFieldEdit) {
        let tookToken = edit.tokens.count > tokens.count
        if tokens != edit.tokens { tokens = edit.tokens }
        if text != edit.text { text = edit.text }
        // The suggestions for the text that became a token go at once, so a second tap cannot
        // take a row for text that is gone.
        if tookToken { suggestions.textDidChange("") }
        // Each call cancels the lookup before it.
        suggestions.textDidChange(TagSuggestionModel.normalize(SearchTokens.lookupText(beforeCaret: edit.beforeCaret)))
    }

    /// New content for the field (a recent search, a quick search, the keyword of the results
    /// the surface was opened from; `""` empties it): its tags as tokens, the rest as text.
    /// The only way content goes in; it bumps `revision`. Suggestions are for typing, so a
    /// keyword handed in shows none until the next keystroke.
    public func replaceKeyword(_ keyword: String) {
        let split = SearchTokens.split(TagSuggestionModel.normalize(keyword))
        var seen = Set<SearchToken>()
        tokens = split.tokens.filter { seen.insert($0).inserted }
        text = split.remainder
        revision += 1
        suggestions.textDidChange("")
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

    /// "Open": reads the link (the system may ask to paste) and withdraws the offer. Returns
    /// the app's own link for it (`EhURL.appLink`), which the caller opens as a shared link
    /// opens; `nil` when the clipboard held no link to a gallery, which a design may say.
    public func openLink() -> URL? {
        hasLinkOffer = false
        return clipboard.url().flatMap(EhURL.appLink(for:))
    }
}
