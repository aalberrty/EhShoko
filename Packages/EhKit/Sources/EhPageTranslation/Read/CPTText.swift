import Foundation

/// manga-ocr's greedy decoding: from the start token, one decoder step for each position, each
/// step fed the token the last one chose, until the end token or the last position of the
/// cache. The end token is not part of the result.
struct GreedyDecoding: Sendable {
    let start: Int
    let end: Int
    /// The positions of the decoder's cache: at most this many steps.
    let maximumSteps: Int

    /// Runs `step(token, position)`, which returns the next token, and gives the tokens chosen.
    /// Checks for cancellation before each step.
    func run(_ step: (_ token: Int, _ position: Int) async throws -> Int) async throws -> [Int] {
        var tokens: [Int] = []
        var token = start
        for position in 0..<maximumSteps {
            try Task.checkCancellation()
            token = try await step(token, position)
            if token == end { break }
            tokens.append(token)
        }
        return tokens
    }
}

/// The text of a list of CPT tokens, as manga-ocr writes it: the vocabulary's pieces with the
/// special tokens (ids below 5) left out and "##" dropped, whitespace removed, "…" as three
/// dots, a run of two or more ・ or . as that many dots, and ASCII as full-width characters.
struct CPTText: Sendable {
    static let firstOrdinaryToken = 5
    let vocabulary: [String]

    init(vocabulary: [String]) {
        self.vocabulary = vocabulary
    }

    /// The vocabulary file: one piece a line, the line's number its id.
    init(contentsOf url: URL) throws {
        let text = try String(contentsOf: url, encoding: .utf8)
        // Lines end as Python's universal newlines end them; "\r\n" is one Character in Swift.
        vocabulary = text.split(omittingEmptySubsequences: false) { $0 == "\n" || $0 == "\r\n" || $0 == "\r" }
            .map(String.init)
    }

    func text(_ tokens: [Int]) -> String {
        var joined = ""
        for token in tokens where token >= Self.firstOrdinaryToken && token < vocabulary.count {
            let piece = vocabulary[token]
            joined += piece.hasPrefix("##") ? String(piece.dropFirst(2)) : piece
        }
        return Self.postprocess(joined)
    }

    static func postprocess(_ text: String) -> String {
        let compact = String(String.UnicodeScalarView(text.unicodeScalars.filter { !$0.properties.isWhitespace }))
            .replacingOccurrences(of: "…", with: "...")
        var dotted = ""
        var run: [Character] = []
        func flush() {
            dotted += run.count >= 2 ? String(repeating: ".", count: run.count) : String(run)
            run.removeAll()
        }
        for character in compact {
            if character == "・" || character == "." {
                run.append(character)
            } else {
                flush()
                dotted.append(character)
            }
        }
        flush()
        return String(String.UnicodeScalarView(dotted.unicodeScalars.map { scalar in
            (0x21...0x7E).contains(scalar.value) ? Unicode.Scalar(scalar.value + 0xFEE0) ?? scalar : scalar
        }))
    }
}
