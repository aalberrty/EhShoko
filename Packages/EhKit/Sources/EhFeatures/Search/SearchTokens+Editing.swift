import Foundation

/// What the search field holds after an edit: its tokens and text, and the text from the
/// start of its textual part to the caret, which is what tag suggestions are looked up for.
nonisolated public struct TagSearchFieldEdit: Equatable, Sendable {
    public var tokens: [SearchToken]
    public var text: String
    public var beforeCaret: String

    public init(tokens: [SearchToken], text: String, beforeCaret: String) {
        self.tokens = tokens
        self.text = text
        self.beforeCaret = beforeCaret
    }

    public static let empty = TagSearchFieldEdit(tokens: [], text: "", beforeCaret: "")
}

/// The search field's small text rules (`spikes/S6.md` sections 2 to 4), kept apart from
/// UIKit so they read, and are tested, as rules.
nonisolated extension SearchTokens {
    /// The marks a term may start with: `-` leaves the tag out, `~` makes it one of several.
    public static let marks: Set<Character> = ["-", "~"]

    /// The text to look tag suggestions up for: the text before the caret, with the last
    /// word's `-` or `~` dropped, because the dictionary has no `-glasses`. The token that a
    /// suggestion becomes gets the mark back (`replacement(for:keyword:beforeCaret:)`).
    public static func lookupText(beforeCaret text: String) -> String {
        guard let mark = lastWordMark(in: text) else { return text }
        var text = text
        text.remove(at: mark)
        return text
    }

    /// Where the last word of `text` starts with a mark, if it does.
    private static func lastWordMark(in text: String) -> String.Index? {
        let start = text.lastIndex(where: \.isWhitespace).map(text.index(after:)) ?? text.startIndex
        return start < text.endIndex && marks.contains(text[start]) ? start : nil
    }

    /// A namespace key (`artist:`) typed right after a word starts a new term, so it gets a
    /// space before it; after a space, a mark or at the start it goes in as it is. `-` and `$`
    /// always go in as they are.
    public static func needsSpace(beforeKey key: String, after previous: Character?) -> Bool {
        guard key.hasSuffix(":"), let previous else { return false }
        return !previous.isWhitespace && !marks.contains(previous)
    }

    /// The complete term just before a space typed at the caret, which becomes a token:
    /// `f:kimono$ ` gives `f:kimono$`. `nil` when the text before the caret does not end with
    /// a space after a complete term.
    public static func completedTerm(beforeCaret text: String) -> String? {
        guard text.last == " " else { return nil }
        let body = text.dropLast()
        let start = body.lastIndex(where: \.isWhitespace).map(body.index(after:)) ?? body.startIndex
        let word = String(body[start...])
        // A quoted tag has a space inside; the space after it closes it only once the quote is.
        if word.hasPrefix("\"") || word.contains(":\"") || word.hasSuffix("\"") {
            return quotedTerm(endingAt: body)
        }
        return SearchToken(term: word) == nil ? nil : word
    }

    /// The quoted term that ends `text` (`f:"big breasts$"`), found by walking back to the
    /// quote that opens it.
    private static func quotedTerm(endingAt text: Substring) -> String? {
        guard text.hasSuffix("$\""), let close = text.indices.last else { return nil }
        guard let open = text[..<close].lastIndex(of: "\"") else { return nil }
        let start = text[..<open].lastIndex(where: \.isWhitespace).map(text.index(after:)) ?? text.startIndex
        let term = String(text[start...])
        return SearchToken(term: term) == nil ? nil : term
    }

    /// How a chosen suggestion replaces the end of the text before the caret: `length` UTF-16
    /// units step back over the fragment it matched (and over the mark the lookup dropped),
    /// and `term` is the token's term, with that mark. `nil` when the text no longer ends with
    /// the fragment, for example after the caret moved.
    public static func replacement(
        for fragment: String, keyword: String, beforeCaret text: String
    ) -> (length: Int, term: String)? {
        let lookup = lookupText(beforeCaret: text)
        guard let length = matchedLength(of: fragment, atEndOf: lookup) else { return nil }
        // A fragment is made of whole words, so it covers the last word and the mark before it.
        guard let mark = lastWordMark(in: text) else { return (length, keyword) }
        return (length + 1, String(text[mark]) + keyword)
    }

    /// Whether `fragment` ends `text`, ignoring case and the runs of spaces the lookup
    /// collapsed, as the length of the matching end of `text` in UTF-16 units.
    private static func matchedLength(of fragment: String, atEndOf text: String) -> Int? {
        let fragment = TagSuggestionModel.normalize(fragment)
        guard !fragment.isEmpty else { return nil }
        let normalized = TagSuggestionModel.normalize(text)
        guard normalized.lowercased().hasSuffix(fragment.lowercased()) else { return nil }
        // Walk back over `text` itself, so collapsed spaces count as typed.
        var remaining = fragment.count
        var index = text.endIndex
        var previousWasSpace = false
        while remaining > 0, index > text.startIndex {
            index = text.index(before: index)
            let isSpace = text[index] == " "
            if !(isSpace && previousWasSpace) { remaining -= 1 }
            previousWasSpace = isSpace
        }
        return text[index...].utf16.count
    }
}
