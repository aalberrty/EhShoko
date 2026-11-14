import Foundation

/// A gallery title split into the parts of the site's naming convention,
/// `(event) [circle (artist)] title (parody) [language] [translator] [flags…]`.
///
/// Display logic over titles people type by hand: when a title does not fit the convention,
/// `core` is the raw title, every other part is empty and `isParsed` is `false`, so a row shows
/// the title as it is rather than a wrong guess.
public struct ParsedTitle: Hashable, Sendable {
    /// The title itself, without the bracketed groups around it.
    public var core: String
    /// The event it was released at, e.g. "C103".
    public var event: String?
    public var circle: String?
    public var artists: [String]
    /// The work it parodies, or the magazine it ran in: whatever the convention's first
    /// parenthesised group after the title holds.
    public var parody: String?
    /// The language group as written ("English", "中国翻訳"); `TitleParser.language(named:)`
    /// reads it as a `Language`.
    public var language: String?
    public var translator: String?
    /// Release notes such as "Digital", "DL版", "Incomplete", in title order.
    public var flags: [String]
    public var isParsed: Bool

    /// An unparsed title: `core` is `raw` and every other part is empty.
    public init(raw: String) {
        self.init(core: raw, isParsed: false)
    }

    public init(
        core: String, event: String? = nil, circle: String? = nil, artists: [String] = [],
        parody: String? = nil, language: String? = nil, translator: String? = nil,
        flags: [String] = [], isParsed: Bool = true
    ) {
        self.core = core
        self.event = event
        self.circle = circle
        self.artists = artists
        self.parody = parody
        self.language = language
        self.translator = translator
        self.flags = flags
        self.isParsed = isParsed
    }
}

/// Parses gallery titles into `ParsedTitle`. Pure and allocation-light: list pages run it once
/// per gallery when the page is mapped, off the main actor.
public enum TitleParser {
    public static func parse(_ title: String) -> ParsedTitle {
        // A `|` joins two versions of the title (romanised | original); neither half can be
        // told from the groups reliably.
        guard !title.unicodeScalars.contains("|"),
              let parsed = TitleScanner(title).parse()
        else { return ParsedTitle(raw: title) }
        return parsed
    }

    /// The language a title's language group names: a site language ("English", "spanish"),
    /// the Japanese labels ("中国翻訳", "英訳", "日本語"), or several separated by "、" or ","
    /// (the first one counts). `nil` when the text is not a language.
    public static func language(named text: String) -> Language? {
        let parts = text.split(whereSeparator: { $0 == "、" || $0 == "," })
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard !parts.isEmpty else { return nil }
        var first: Language?
        for part in parts {
            guard let language = singleLanguage(part) else { return nil }
            first = first ?? language
        }
        return first
    }

    private static func singleLanguage(_ text: String) -> Language? {
        if let language = Language(rawValue: text.capitalized), language != .invalid, language != .other {
            return language
        }
        if text == "英訳" { return .english }
        if text == "汉化" || text == "漢化" { return .chinese }
        for suffix in ["翻訳", "語"] where text.hasSuffix(suffix) {
            return japaneseLanguageNames[String(text.dropLast(suffix.count))]
        }
        return nil
    }

    /// The Japanese names the site's titles use before 翻訳 ("translation") or 語 ("language").
    private static let japaneseLanguageNames: [String: Language] = [
        "中国": .chinese, "英": .english, "英国": .english, "韓国": .korean, "日本": .japanese,
        "ロシア": .russian, "ドイツ": .german, "スペイン": .spanish, "ポルトガル": .portuguese,
        "フランス": .french, "イタリア": .italian, "インドネシア": .indonesian, "ウクライナ": .ukrainian,
        "タイ": .thai, "ベトナム": .vietnamese, "ポーランド": .polish, "オランダ": .dutch,
        "ハンガリー": .hungarian, "トルコ": .turkish, "アラビア": .arabic, "チェコ": .czech
    ]

    /// Trailing groups that are release notes rather than a language or a translator,
    /// lowercased.
    static let flags: Set<String> = [
        "dl版", "digital", "decensored", "uncensored", "無修正", "censored", "colorized", "colourized",
        "カラー化", "full color", "full colour", "全彩", "incomplete", "ページ欠落", "ongoing", "進行中",
        "complete", "見本", "sample", "preview", "textless", "rewrite", "renamed", "ai generated",
        "ai-generated", "ai_generated", "hd", "修正版", "雑誌寄せ集め"
    ]

    /// Labels of where a gallery was collected from, which take the credit's place in dumps
    /// ("[Pixiv] name (id)"); such titles do not follow the convention. Lowercased.
    static let sourceLabels: Set<String> = [
        "pixiv", "fanbox", "patreon", "fantia", "twitter", "artist", "アーティスト", "rule34", "skeb",
        "ci-en", "subscribestar", "gumroad"
    ]

    /// Words that mark a bracket group as a translator or scanlation group.
    static let translatorMarks = ["汉化", "漢化", "翻译", "翻譯", "字幕", "scan", "translat"]
}

/// One pass over a title's Unicode scalars. Only ASCII brackets delimit groups; full-width
/// brackets are ordinary title text, so a title that opens with one does not fit.
private struct TitleScanner {
    private let scalars: [Unicode.Scalar]

    init(_ title: String) {
        scalars = Array(title.unicodeScalars)
    }

    private struct Group {
        let opener: Unicode.Scalar
        let content: String
        /// Whether title text runs straight into the group with no space before it.
        let isAttached: Bool
    }

    func parse() -> ParsedTitle? {
        var result = ParsedTitle(core: "")
        var start = skipSpaces(from: 0)

        // Chinese translations often lead with their group: "[某汉化组] (C97) [circle] title".
        if let translator = group(at: start, opener: "[", closer: "]", allowsParens: false) {
            let afterIt = skipSpaces(from: translator.end)
            if afterIt < scalars.count, scalars[afterIt] == "(" {
                result.translator = translator.content
                start = afterIt
            }
        }
        if let event = group(at: start, opener: "(", closer: ")", allowsParens: true) {
            result.event = event.content
            start = skipSpaces(from: event.end)
        }
        if let credit = group(at: start, opener: "[", closer: "]", allowsParens: true) {
            guard applyCredit(credit.content, to: &result) else { return nil }
            start = skipSpaces(from: credit.end)
        }
        // A title without an event or a credit in front is not in the convention.
        guard result.event != nil || result.circle != nil || !result.artists.isEmpty else { return nil }

        guard var (trailing, coreEnd) = trailingGroups(after: start) else { return nil }
        absorbCoreParentheses(&trailing, coreEnd: &coreEnd)
        guard let core = core(from: start, to: coreEnd) else { return nil }
        result.core = core
        guard classify(trailing, into: &result) else { return nil }
        return result
    }

    // MARK: Groups

    /// The bracketed group opening at `index`, its content trimmed, and the index after it.
    /// `nil` when there is none, it is unbalanced, empty, or holds a nested group of its own
    /// kind (parentheses may nest inside parentheses, and inside a bracket group when allowed).
    private func group(
        at index: Int, opener: Unicode.Scalar, closer: Unicode.Scalar, allowsParens: Bool
    ) -> (content: String, end: Int)? {
        guard index < scalars.count, scalars[index] == opener else { return nil }
        var depth = 0
        var parenDepth = 0
        var cursor = index
        while cursor < scalars.count {
            let scalar = scalars[cursor]
            if scalar == opener {
                depth += 1
                if depth > 1 && opener != "(" { return nil }
            } else if scalar == closer {
                depth -= 1
                if depth == 0 {
                    guard parenDepth == 0, let content = text(index + 1, cursor) else { return nil }
                    return (content, cursor + 1)
                }
            } else if opener != "(", scalar == "(" || scalar == ")" {
                guard allowsParens else { return nil }
                parenDepth += scalar == "(" ? 1 : -1
                if parenDepth < 0 { return nil }
            } else if isBracket(scalar) {
                return nil
            }
            cursor += 1
        }
        return nil
    }

    /// The groups at the end of the title, in title order, and where the title text before them
    /// ends. `nil` when a closing bracket there has no opening one.
    private func trailingGroups(after start: Int) -> ([Group], Int)? {
        var groups: [Group] = []
        var end = scalars.count
        while true {
            end = skipSpacesBackward(from: end, limit: start)
            guard end > start, isCloser(scalars[end - 1]) else { break }
            let closer = scalars[end - 1]
            let opener: Unicode.Scalar = closer == ")" ? "(" : closer == "]" ? "[" : "{"
            guard let openIndex = matchingOpener(for: end - 1, opener: opener, limit: start),
                  let content = text(openIndex + 1, end - 1)
            else { return nil }
            let attached = openIndex > start && !isSpace(scalars[openIndex - 1]) && !isCloser(scalars[openIndex - 1])
            groups.append(Group(opener: opener, content: content, isAttached: attached))
            end = openIndex
        }
        return (groups.reversed(), end)
    }

    private func matchingOpener(for closeIndex: Int, opener: Unicode.Scalar, limit: Int) -> Int? {
        let closer = scalars[closeIndex]
        var depth = 0
        var cursor = closeIndex
        while cursor >= limit {
            let scalar = scalars[cursor]
            if scalar == closer {
                depth += 1
                if depth > 1 && closer != ")" { return nil }
            } else if scalar == opener {
                depth -= 1
                if depth == 0 { return cursor }
            } else if closer == ")", isBracket(scalar) {
                return nil
            } else if closer != ")", scalar != "(", scalar != ")", isBracket(scalar) {
                return nil
            }
            cursor -= 1
        }
        return nil
    }

    /// A parenthesised group that belongs to the title text rather than after it: a number
    /// ("(2023)", "(1)"), or one written onto the title with another parenthesised group
    /// following ("…奮闘記(前編) (Fate/stay night)").
    private func absorbCoreParentheses(_ groups: inout [Group], coreEnd: inout Int) {
        while let first = groups.first, first.opener == "(" {
            let isNumber = first.content.unicodeScalars.allSatisfy { CharacterSet.decimalDigits.contains($0) }
            let isAttachedBeforeParens = first.isAttached && groups.count > 1 && groups[1].opener == "("
            guard isNumber || isAttachedBeforeParens else { return }
            groups.removeFirst()
            coreEnd = skipSpaces(from: coreEnd)
            coreEnd = closingIndex(fromOpener: coreEnd) + 1
        }
    }

    private func closingIndex(fromOpener index: Int) -> Int {
        var depth = 0
        var cursor = index
        while cursor < scalars.count {
            if scalars[cursor] == "(" { depth += 1 }
            if scalars[cursor] == ")" {
                depth -= 1
                if depth == 0 { return cursor }
            }
            cursor += 1
        }
        return scalars.count - 1
    }

    // MARK: Parts

    /// "circle (artist, artist)" or "artist, artist". `false` for a collection-source label.
    private func applyCredit(_ content: String, to result: inout ParsedTitle) -> Bool {
        if content.hasSuffix(")"), let open = content.range(of: "(", options: .backwards) {
            let circle = content[..<open.lowerBound].trimmingCharacters(in: .whitespaces)
            let artists = String(content[open.upperBound...].dropLast())
            result.circle = circle.isEmpty ? nil : circle
            result.artists = Self.names(in: artists)
        } else {
            let labels = content.split(separator: "/").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            if labels.allSatisfy(TitleParser.sourceLabels.contains) { return false }
            result.artists = Self.names(in: content)
        }
        return result.circle != nil || !result.artists.isEmpty
    }

    private static func names(in text: String) -> [String] {
        text.split(whereSeparator: { $0 == "," || $0 == "、" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// The title text: trimmed, without a leading "- " ("[Circle] - Title"), and holding no
    /// bracket groups or unbalanced parentheses of its own.
    private func core(from start: Int, to end: Int) -> String? {
        guard start < end else { return nil }
        var depth = 0
        for scalar in scalars[start..<end] {
            switch scalar {
            case "[", "]", "{", "}": return nil
            case "(": depth += 1
            case ")":
                depth -= 1
                if depth < 0 { return nil }
            default: break
            }
        }
        guard depth == 0, var core = text(start, end) else { return nil }
        if core.hasPrefix("-") {
            core = core.dropFirst().trimmingCharacters(in: .whitespaces)
        }
        return core.isEmpty ? nil : core
    }

    /// Sorts the trailing groups into parody, language, translator and flags. `false` when a
    /// bracket group is none of these.
    private func classify(_ groups: [Group], into result: inout ParsedTitle) -> Bool {
        var seenBracket = false
        for group in groups {
            let lowered = group.content.lowercased()
            switch group.opener {
            case "(":
                let parts = group.content.split(separator: "/").map { $0.trimmingCharacters(in: .whitespaces) }
                if result.language == nil, TitleParser.language(named: group.content) != nil {
                    result.language = group.content
                } else if parts.allSatisfy({ TitleParser.flags.contains($0.lowercased()) }) {
                    result.flags.append(contentsOf: parts)
                } else if result.parody == nil, !seenBracket {
                    result.parody = group.content
                } else {
                    result.flags.append(group.content)
                }
            case "{":
                // "{2d-market.com}", "{Translator}": notes on who released it.
                if result.translator == nil { result.translator = group.content }
            default:
                seenBracket = true
                if result.language == nil, TitleParser.language(named: group.content) != nil {
                    result.language = group.content
                } else if TitleParser.flags.contains(lowered) {
                    result.flags.append(group.content)
                } else if result.translator == nil,
                          result.language != nil || TitleParser.translatorMarks.contains(where: lowered.contains) {
                    result.translator = group.content
                } else {
                    return false
                }
            }
        }
        return true
    }

    // MARK: Scalars

    private func text(_ start: Int, _ end: Int) -> String? {
        guard start < end else { return nil }
        var view = String.UnicodeScalarView()
        view.append(contentsOf: scalars[start..<end])
        let text = String(view).trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : text
    }

    private func skipSpaces(from index: Int) -> Int {
        var index = index
        while index < scalars.count, isSpace(scalars[index]) { index += 1 }
        return index
    }

    private func skipSpacesBackward(from index: Int, limit: Int) -> Int {
        var index = index
        while index > limit, isSpace(scalars[index - 1]) { index -= 1 }
        return index
    }

    private func isSpace(_ scalar: Unicode.Scalar) -> Bool {
        scalar.properties.isWhitespace
    }

    private func isCloser(_ scalar: Unicode.Scalar) -> Bool {
        scalar == ")" || scalar == "]" || scalar == "}"
    }

    private func isBracket(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar {
        case "(", ")", "[", "]", "{", "}": true
        default: false
        }
    }
}
