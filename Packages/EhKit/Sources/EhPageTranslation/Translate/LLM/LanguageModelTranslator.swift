import EhModels
import Foundation

/// A language model as a page translator: GalTransl v4 4B, Sakura 1.5B, Hy-MT2 1.8B or
/// Qwen3.5 4B.
///
/// The whole page goes to the model in one request, as numbered lines, and numbered lines
/// come back; that is how these models were compared, and it lets a line be translated with
/// the lines around it. A page too long for one request is asked for in two halves, each
/// numbered from 1, and a half in halves again if it must be.
///
/// Calls may overlap, but an engine generates one answer at a time, so the second waits.
public struct LanguageModelTranslator: PageTranslator {
    public let profile: LanguageModelProfile
    private let engine: any TextGenerationEngine

    public init(profile: LanguageModelProfile, engine: any TextGenerationEngine) {
        self.profile = profile
        self.engine = engine
    }

    /// One result for each line, in the same order. `nil` for a line the answer does not
    /// have, for a blank line, and for a line that is too long for the model even alone.
    ///
    /// Throws `CancellationError` when the calling task is cancelled or `stop()` is called
    /// while the page is in work: a page is never returned half translated.
    @concurrent
    public func translate(_ lines: [String]) async throws -> [String?] {
        try await translateRecording(lines).lines
    }

    /// Ends the page that is in work, within one token of the model: its `translate` throws
    /// `CancellationError`. For whoever unloads the model without owning the task.
    public func stop() {
        engine.stop()
    }

    /// `translate`, with what each request to the model was and gave: for measuring.
    @concurrent
    public func translateRecording(_ lines: [String]) async throws -> LanguageModelPage {
        var page = LanguageModelPage(lines: [String?](repeating: nil, count: lines.count), requests: [])
        // A blank line is nothing to translate, and would be a number with no text.
        let asked = lines.indices.filter { !lines[$0].allSatisfy(\.isWhitespace) }
        try await translate(asked[...], of: lines, into: &page)
        return page
    }

    private func translate(
        _ indices: ArraySlice<Int>, of lines: [String], into page: inout LanguageModelPage
    ) async throws {
        guard !indices.isEmpty else { return }
        try Task.checkCancellation()
        let source = indices.map { lines[$0] }
        let prompt = profile.prompt.text(for: source)
        let promptTokens = try await engine.tokenCount(of: prompt)
        let sourceTokens = try await engine.tokenCount(of: NumberedLines.text(source))
        let fits = profile.holds(
            promptTokens: promptTokens, sourceTokens: sourceTokens, contextLength: engine.contextLength
        )
        guard fits else {
            // One line that does not fit stays as it is.
            guard indices.count > 1 else { return }
            let middle = indices.startIndex + (indices.count + 1) / 2
            try await translate(indices[..<middle], of: lines, into: &page)
            try await translate(indices[middle...], of: lines, into: &page)
            return
        }

        let generation = try await engine.generate(prompt, options: profile.options(sourceTokens: sourceTokens))
        // A stopped answer ends anywhere. The page is given up rather than kept in part.
        guard generation.finish != .stopped else { throw CancellationError() }
        try Task.checkCancellation()
        let isCutOff = generation.finish != .endOfGeneration
        let translations = NumberedLines.parse(generation.text, count: source.count, isCutOff: isCutOff)
        for (index, translation) in zip(indices, translations) {
            page.lines[index] = translation
        }
        page.requests.append(
            LanguageModelPage.Request(
                lineIndices: Array(indices), prompt: prompt, sourceTokens: sourceTokens, generation: generation
            )
        )
    }
}

/// A page's translations, and the requests that made them.
public struct LanguageModelPage: Sendable, Equatable {
    public struct Request: Sendable, Equatable {
        /// Which of the page's lines were asked for, in order.
        public var lineIndices: [Int]
        public var prompt: String
        /// The tokens of the numbered lines alone, without the words around them.
        public var sourceTokens: Int
        public var generation: TextGeneration
    }

    public var lines: [String?]
    /// One for a page that fits, more for a page that was split, none for a page with
    /// nothing to translate.
    public var requests: [Request]
}

extension PageTranslatorLoader {
    /// A `languageModel` loader over any engine: `engine` loads the model file with the
    /// profile's context, and the translator of the choice is built on it.
    public static func languageModelLoader(
        engine: @escaping @Sendable (_ file: URL, _ profile: LanguageModelProfile) async throws
            -> any TextGenerationEngine
    ) -> LanguageModelLoader {
        { choice, file in
            guard let profile = LanguageModelProfile(choice) else { throw PageTranslatorError.unavailable(choice) }
            return LanguageModelTranslator(profile: profile, engine: try await engine(file, profile))
        }
    }
}
