import EhFeatures

/// Makes `SearchSurfaceModel` follow the field (`spikes/S6.md` section 11, "The model").
///
/// The spike's model takes the field's edit in one call (`fieldDidEdit`) and looks
/// suggestions up for the text before the caret. The model as built has no such call: its
/// text drives the lookup for the whole text, and its tokens change only through its editing
/// methods. Until it gains one, this file does the same with what the model offers, and it is
/// the only place that has to change when it does.
@MainActor
enum TagSearchFieldMirror {
    static func fieldDidEdit(_ edit: TagSearchFieldEdit, model: SearchSurfaceModel) {
        let tookToken = edit.tokens.count > model.tokens.count
        if model.tokens != edit.tokens {
            if isRemoval(from: model.tokens, to: edit.tokens) {
                for token in model.tokens where !edit.tokens.contains(token) {
                    model.removeToken(token)
                }
            } else {
                // Replaces the tokens and empties the text, which is set again below.
                model.use(SearchTokens(tokens: edit.tokens).keyword)
            }
        }
        if model.text != edit.text {
            model.text = edit.text
        }
        // A token was taken: the list of suggestions for the text that became it goes at
        // once, so a second tap cannot take a row for text that is gone.
        if tookToken {
            model.suggestions.textDidChange("")
        }
        // The lookup the model's text asked for is replaced by the one for the text before
        // the caret, without the last word's mark; each call cancels the one before.
        model.suggestions.textDidChange(
            TagSuggestionModel.normalize(TagSearchFieldRules.lookupText(beforeCaret: edit.beforeCaret))
        )
    }

    /// Whether `new` is `old` with some tokens deleted, in the same order.
    private static func isRemoval(from old: [SearchToken], to new: [SearchToken]) -> Bool {
        guard new.count < old.count else { return false }
        var remaining = new[...]
        for token in old where remaining.first == token {
            remaining = remaining.dropFirst()
        }
        return remaining.isEmpty
    }
}
