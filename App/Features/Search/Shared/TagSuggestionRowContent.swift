import EhFeatures
import EhModels
import Foundation

/// What a tag suggestion row shows, worked out once per page of suggestions (`shelf.md`,
/// `wall.md`, `ledger.md` section 6): the namespace in its colour, the tag with the typed
/// part bold, and the translated name. Each design lays the row out its own way; a row view
/// takes this value and reads nothing else.
nonisolated struct TagSuggestionRowContent: Identifiable, Equatable, Sendable {
    /// The suggestion, which `TagSearchFieldController.accept(_:)` turns into a token.
    let item: SearchTagSuggestion
    let namespace: TagNamespace
    /// The tag, with the part the text matched bold.
    let tag: AttributedString
    /// The translated name, with the part the text matched bold; the plain tag again when the
    /// dictionary has no name for it.
    let translation: AttributedString
    /// Whether the typed text named the namespace (`f:gla`), which a design may mark.
    let matchesNamespace: Bool
    /// "female, glasses, 眼镜": one element for VoiceOver, as the row is.
    let accessibilityLabel: String

    var id: String { item.id }

    @MainActor
    init(_ item: SearchTagSuggestion) {
        let suggestion = item.suggestion
        self.item = item
        namespace = suggestion.tag.namespace
        tag = Self.bolding(suggestion.tag.key, at: suggestion.keyRange)
        translation = Self.bolding(item.displayValue, at: suggestion.valueRange)
        matchesNamespace = suggestion.matchesNamespace
        accessibilityLabel = [suggestion.tag.namespace.localizedName, suggestion.tag.key, item.displayValue]
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    /// The rows for a page of suggestions, in the order the model ranked them.
    @MainActor
    static func rows(for suggestions: [SearchTagSuggestion]) -> [TagSuggestionRowContent] {
        suggestions.map(TagSuggestionRowContent.init)
    }

    /// `string` with the part at `range` bold. The range may come from another rendering of
    /// the text (`TagSuggestion.segments`), so it is cut defensively.
    private static func bolding(_ string: String, at range: Range<String.Index>?) -> AttributedString {
        let parts = TagSuggestion.segments(of: string, around: range)
        var match = AttributedString(parts.match)
        match.inlinePresentationIntent = .stronglyEmphasized
        return AttributedString(parts.before) + match + AttributedString(parts.after)
    }
}
