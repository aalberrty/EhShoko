import Foundation

/// A page as a language model is given it and as it answers: one line for each block, each
/// starting with its number.
enum NumberedLines {
    /// `1: first` and so on, one line each. A line break inside a block would start a line
    /// without a number, so it becomes a space.
    static func text(_ lines: [String]) -> String {
        lines.enumerated()
            .map { "\($0.offset + 1): \(singleLine($0.element))" }
            .joined(separator: "\n")
    }

    static func singleLine(_ text: String) -> String {
        guard text.contains(where: \.isNewline) else { return text }
        return text.split(omittingEmptySubsequences: true, whereSeparator: \.isNewline).joined(separator: " ")
    }

    /// The answer's lines by their numbers: `count` results, `nil` for a number the answer
    /// does not have or has nothing after.
    ///
    /// These are the rules the compared outputs were read with, so the figures describe what
    /// the app shows. The models write the number in more than one way (`3: `, `3：`, `3. `,
    /// `(3)`), sometimes within one answer. A number's first line counts and a second one
    /// does not; a line without a number, or with one the page does not have, belongs to no
    /// block and is left out, whether it is a preface, a remark or the rest of a translation
    /// the model broke in two.
    ///
    /// - Parameter isCutOff: The generation ran into a limit, so the last line may end in the
    ///   middle of a sentence. It is left out unless a line break follows it.
    static func parse(_ answer: String, count: Int, isCutOff: Bool = false) -> [String?] {
        var results = [String?](repeating: nil, count: count)
        guard count > 0 else { return results }
        var seen = Set<Int>()
        for line in lines(of: answer, isCutOff: isCutOff) {
            guard let (number, text) = numbered(line), (1...count).contains(number), seen.insert(number).inserted
            else { continue }
            results[number - 1] = text.isEmpty ? nil : text
        }
        return results
    }

    private static func lines(of answer: String, isCutOff: Bool) -> [Substring] {
        var text = Substring(withoutThinking(answer))
        if isCutOff {
            // Everything after the last line break is the line that was being written.
            guard let lastBreak = text.lastIndex(where: \.isNewline) else { return [] }
            text = text[..<lastBreak]
        }
        return text.split(omittingEmptySubsequences: true, whereSeparator: \.isNewline)
    }

    /// The answer without the blocks a model thinks aloud in. An opened block that is never
    /// closed stays: nothing says where it would end.
    private static func withoutThinking(_ answer: String) -> String {
        var text = answer
        while let open = text.range(of: "<think>"),
              let close = text.range(of: "</think>", range: open.upperBound..<text.endIndex) {
            text.removeSubrange(open.lowerBound..<close.upperBound)
        }
        return text
    }

    /// A line's number and what follows it: optional white space, an opening bracket, the
    /// digits, a closing bracket, one separator, then the text.
    private static func numbered(_ line: Substring) -> (number: Int, text: String)? {
        var rest = line.drop(while: \.isWhitespace)
        if let first = rest.first, openingBrackets.contains(first) {
            rest = rest.dropFirst().drop(while: \.isWhitespace)
        }
        var number = 0
        var digits = 0
        while let digit = rest.first.flatMap(decimalDigit) {
            // A number this long is no line of a page; it must only not overflow.
            number = min(number * 10 + digit, 1_000_000)
            digits += 1
            rest = rest.dropFirst()
        }
        guard digits > 0 else { return nil }
        rest = rest.drop(while: \.isWhitespace)
        if let first = rest.first, closingBrackets.contains(first) {
            rest = rest.dropFirst().drop(while: \.isWhitespace)
        }
        if let first = rest.first, separators.contains(first) {
            rest = rest.dropFirst()
        }
        return (number, rest.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static let openingBrackets: Set<Character> = ["[", "(", "（", "【"]
    private static let closingBrackets: Set<Character> = ["]", ")", "）", "】"]
    private static let separators: Set<Character> = [":", "：", ".", "．", "、", ")", "）", "|"]

    /// The value of a decimal digit of any script (the models also write full-width ones).
    private static func decimalDigit(_ character: Character) -> Int? {
        let scalars = character.unicodeScalars
        guard scalars.count == 1, let scalar = scalars.first,
              scalar.properties.generalCategory == .decimalNumber,
              let value = scalar.properties.numericValue
        else { return nil }
        return Int(value)
    }
}
