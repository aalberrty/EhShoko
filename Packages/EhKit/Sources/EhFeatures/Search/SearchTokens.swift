import Foundation

/// One accepted tag in a search: an exact `namespace:tag$` term, which the search field shows
/// as a token instead of as text.
nonisolated public struct SearchToken: Hashable, Sendable, Identifiable {
    /// The term as the site receives it, e.g. `f:"big breasts$"` or `-artist:glacier$`.
    public let term: String
    /// The namespace as written (`f`, `female`), or `nil` for a tag without one.
    public let namespace: String?
    /// The tag without its quotes and `$`, e.g. `big breasts`.
    public let tag: String
    /// A `-` term: galleries with the tag are left out.
    public let isExcluded: Bool

    public var id: String { term }

    /// `term` as a token, or `nil` when it is not an exact tag term.
    public init?(term: String) {
        var body = Substring(term)
        let isExcluded = body.first == "-"
        if isExcluded { body = body.dropFirst() }
        var namespace: String?
        if let colon = body.firstIndex(of: ":"), !body[..<colon].contains("\"") {
            let prefix = body[..<colon]
            guard !prefix.isEmpty else { return nil }
            namespace = String(prefix)
            body = body[body.index(after: colon)...]
        }
        let tag: Substring
        if body.hasPrefix("\""), body.hasSuffix("$\""), body.count > 3 {
            tag = body.dropFirst().dropLast(2)
            guard !tag.contains("\"") else { return nil }
        } else if body.hasSuffix("$"), body.count > 1, !body.contains("\""), !body.contains(" ") {
            tag = body.dropLast()
        } else {
            return nil
        }
        guard !tag.contains("$"), !tag.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        self.term = term
        self.namespace = namespace
        self.tag = String(tag)
        self.isExcluded = isExcluded
    }
}

/// A search keyword as the search field shows it: the accepted tags as tokens, and the rest as
/// text.
nonisolated public struct SearchTokens: Hashable, Sendable {
    public var tokens: [SearchToken]
    /// The terms that are not exact tags, in their order, separated by single spaces.
    public var remainder: String

    public init(tokens: [SearchToken] = [], remainder: String = "") {
        self.tokens = tokens
        self.remainder = remainder
    }

    /// Splits `keyword` into its exact tag terms, wherever they are, and the other terms.
    /// The site matches every term whatever their order, so moving the tags first keeps the
    /// search the same.
    public static func split(_ keyword: String) -> SearchTokens {
        var tokens = [SearchToken]()
        var rest = [String]()
        for term in terms(of: keyword) {
            if let token = SearchToken(term: term) {
                tokens.append(token)
            } else {
                rest.append(term)
            }
        }
        return SearchTokens(tokens: tokens, remainder: rest.joined(separator: " "))
    }

    /// The keyword the site receives: the tokens' terms, then the remainder.
    public var keyword: String {
        (tokens.map(\.term) + [remainder]).filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// The terms of `keyword`, split at whitespace outside double quotes.
    static func terms(of keyword: String) -> [String] {
        var terms = [String]()
        var current = ""
        var isQuoted = false
        for character in keyword {
            if character == "\"" {
                isQuoted.toggle()
                current.append(character)
            } else if character.isWhitespace, !isQuoted {
                if !current.isEmpty { terms.append(current) }
                current = ""
            } else {
                current.append(character)
            }
        }
        if !current.isEmpty { terms.append(current) }
        return terms
    }
}
