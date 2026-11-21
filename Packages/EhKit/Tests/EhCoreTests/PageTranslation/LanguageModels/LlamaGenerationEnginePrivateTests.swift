import EhLlama
import EhModels
import EhPageTranslation
import Foundation
import Testing
@testable import EhCore

/// The opt-in tier for the language models: the real files through llama.cpp, against the run
/// whose outputs were compared blind (`PrivateTranslationFolder`). Serialized, because each
/// model maps gigabytes and uses every core it is given.
@Suite(.privateTranslationFolder, .serialized) struct LlamaGenerationEnginePrivateTests {
    init() {
        LlamaTestEnvironment.keepMetalOff()
    }

    // MARK: Every prompt, counted by the model itself

    /// The prompt of each page is as many tokens for the model as the compared run's server
    /// counted: the words, the template around them and the way it is read into tokens are
    /// the same. The compared answer also fits what one request keeps free for it, so no
    /// compared page would be split or cut.
    @Test(.timeLimit(.minutes(30)), arguments: LanguageModelCandidate.all)
    func everyPromptHasTheComparedRunsTokenCount(candidate: LanguageModelCandidate) async throws {
        let profile = try #require(LanguageModelProfile(candidate.choice))
        let engine = try await LlamaGenerationEngine.load(
            modelAt: candidate.url(), configuration: LlamaConfiguration(contextLength: profile.contextLength)
        )
        #expect(engine.contextLength == profile.contextLength)
        var highestShare = 0.0
        for page in try candidate.comparedPages() {
            let lines = page.lines.map(\.ja)
            let promptTokens = try await engine.tokenCount(of: profile.prompt.text(for: lines))
            let sourceTokens = try await engine.tokenCount(of: lines.enumerated()
                .map { "\($0.offset + 1): \($0.element)" }.joined(separator: "\n"))
            #expect(promptTokens == page.timings.promptN, "\(candidate.name) \(page.page)")
            #expect(
                profile.holds(promptTokens: promptTokens, sourceTokens: sourceTokens, contextLength: engine.contextLength),
                "\(candidate.name) \(page.page) would be split"
            )
            #expect(
                page.timings.predictedN <= LanguageModelProfile.answerReserve(sourceTokens: sourceTokens),
                "\(candidate.name) \(page.page): \(page.timings.predictedN) tokens answered \(sourceTokens)"
            )
            highestShare = max(highestShare, Double(page.timings.predictedN) / Double(sourceTokens))
        }
        await engine.unload()
        print("""
        LlamaGenerationEngine opt-in, \(candidate.name): \(engine.info.summary), context \(engine.contextLength); \
        prompts counted alike on all pages; the longest compared answer had \
        \(String(format: "%.2f", highestShare)) times the tokens of its numbered lines
        """)
    }

    // MARK: One short page, and a stop

    /// The smallest file translates a page of one line, the same way twice; a page stopped
    /// while the model works is given up at once and the model translates again after it.
    @Test(.timeLimit(.minutes(30)))
    func theSmallestModelTranslatesAPageAndStops() async throws {
        let candidate = LanguageModelCandidate.smallest
        let pages = try candidate.comparedPages()
        let short = try #require(pages.first { $0.page == "hayo-16" })
        let long = try #require(pages.first { $0.page == "p2" })
        let translator = try #require(
            try await PageTranslatorLoader.llamaLanguageModel(candidate.choice, candidate.url()) as? LanguageModelTranslator
        )
        let clock = ContinuousClock()

        let first = try await translator.translateRecording(short.lines.map(\.ja))
        let request = try #require(first.requests.first)
        #expect(first.requests.count == 1)
        #expect(request.generation.promptTokens == short.timings.promptN)
        #expect(request.generation.finish == .endOfGeneration)
        #expect(first.lines.allSatisfy { $0 != nil }, "\(request.generation.text)")

        let task = Task { try await translator.translate(long.lines.map(\.ja)) }
        try await Task.sleep(for: .seconds(2))
        let stopStart = clock.now
        translator.stop()
        await #expect(throws: CancellationError.self) { try await task.value }
        let stopTime = clock.now - stopStart

        // The same seed and prompt: the same translation.
        let again = try await translator.translateRecording(short.lines.map(\.ja))
        #expect(again.lines == first.lines)
        print("""
        LlamaGenerationEngine opt-in, \(candidate.name): a page of \(request.generation.promptTokens) prompt tokens \
        in \(request.generation.promptDuration), \(request.generation.generatedTokens) tokens in \
        \(request.generation.generationDuration); a stop two seconds into a longer page returned after \(stopTime)
        """)
    }

    // MARK: The compared pages, translated

    /// Each named model translates the 139 lines of the compared pages, a page a request as
    /// then. Every line comes back; how many equal the compared run's is counted and written
    /// down, not required: that run was another build of llama.cpp with another instruction
    /// set, and a draw can fall the other way on the last digits of a probability.
    ///
    /// The results are written after every page, and a run that was stopped goes on from the
    /// pages it has.
    @Test(.languageModelComparison, .timeLimit(.minutes(480)), arguments: LanguageModelCandidate.asked)
    func translatesTheComparedPages(candidate: LanguageModelCandidate) async throws {
        let file = try PrivateTranslationFolder.reports("MT24/comparison").appending(path: "\(candidate.name).json")
        var run = (try? ComparisonRun.read(file)) ?? ComparisonRun(model: candidate.name, file: candidate.file)
        let clock = ContinuousClock()

        let loadStart = clock.now
        let profile = try #require(LanguageModelProfile(candidate.choice))
        let engine = try await LlamaGenerationEngine.load(
            modelAt: candidate.url(), configuration: LlamaConfiguration(contextLength: profile.contextLength)
        )
        let translator = LanguageModelTranslator(profile: profile, engine: engine)
        run.loadSeconds = (clock.now - loadStart).seconds
        run.modelSummary = engine.info.summary
        run.contextLength = engine.contextLength
        run.systemInfo = try await engine.systemInfo
        run.device = "\(LlamaConfiguration.Device.preferred)"

        for page in try candidate.comparedPages() where !run.pages.contains(where: { $0.page == page.page }) {
            let load = ComparisonRun.loadAverage()
            let start = clock.now
            let result = try await translator.translateRecording(page.lines.map(\.ja))
            run.pages.append(ComparisonRun.Page(page, result: result, wall: (clock.now - start).seconds, load: load))
            try run.write(to: file)
        }
        await engine.unload()

        let pages = run.pages
        #expect(pages.count == 18)
        #expect(pages.allSatisfy { $0.requests == 1 }, "a page was split")
        #expect(pages.allSatisfy { $0.promptTokens == $0.comparedPromptTokens })
        let lines = pages.flatMap(\.lines)
        #expect(lines.count == 139)
        let missing = lines.filter { $0.zh == nil }
        #expect(missing.isEmpty, "\(missing.count) lines did not come back: \(missing.map(\.ja))")
        print(run.summary)
    }
}

// MARK: - The files and the compared run

struct LanguageModelCandidate: Sendable, CustomTestStringConvertible {
    let name: String
    let choice: TranslatorChoice
    /// Inside the private folder.
    let file: String
    /// The model's folder among the compared run's records.
    let compared: String

    var testDescription: String { name }

    /// Hy-MT2 twice: the larger file is the one that was compared, the smaller the one the
    /// phone runs.
    static let all = [
        LanguageModelCandidate(
            name: "hymt2-q4km", choice: .hyMT2, file: "models/llm/dl-hymt2/Hy-MT2-1.8B-Q4_K_M.gguf",
            compared: "hy-mt2-1.8b"
        ),
        LanguageModelCandidate(
            name: "hymt2-q6k", choice: .hyMT2, file: "models/llm/hy-mt2-q6k/Hy-MT2-1.8B-Q6_K.gguf",
            compared: "hy-mt2-1.8b"
        ),
        LanguageModelCandidate(
            name: "sakura", choice: .sakura1_5B, file: "models/llm/sakura-1.5b/sakura-1.5b-qwen2.5-v1.0-Q5KS.gguf",
            compared: "sakura-1.5b"
        ),
        LanguageModelCandidate(
            name: "galtransl", choice: .galTransl4B,
            file: "models/llm/galtransl-v4-4b/Galtransl-v4-4B-2601-Q4_K_M-requant.gguf", compared: "galtransl-v4-4b"
        ),
        LanguageModelCandidate(
            name: "qwen35", choice: .qwen35_4B, file: "models/llm/qwen3.5-4b/Qwen3.5-4B-IQ4_XS.gguf",
            compared: "qwen3.5-4b"
        )
    ]

    static let smallest = all[0]

    /// The candidates `PAGE_TRANSLATION_LANGUAGE_MODELS` names.
    static let asked = all.filter {
        PrivateTranslationFolder.comparedModels.contains($0.name) || PrivateTranslationFolder.comparedModels.contains("all")
    }

    func url() throws -> URL {
        try PrivateTranslationFolder.url(file)
    }

    /// The pages in the order the compared run took them.
    static let pageOrder = [
        "p1", "p2", "p3", "hayo-12", "hayo-13", "hayo-14", "hayo-15", "hayo-16", "hotate-20", "hotate-21",
        "hotate-22", "hotate-23", "hotate-24", "bl-9", "bl-10", "bl-11", "bl-12", "bl-13"
    ]

    func comparedPages() throws -> [ComparedRunPage] {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try Self.pageOrder.map { page in
            let url = try PrivateTranslationFolder.url("research/mt-h2h/raw/\(compared)/\(page).json")
            return try decoder.decode(ComparedRunPage.self, from: Data(contentsOf: url))
        }
    }
}

/// A page of the compared run: its lines, how they were translated, and the server's counts.
struct ComparedRunPage: Decodable {
    struct Line: Decodable {
        let n: Int
        let ja: String
        let zh: String?
    }

    struct Timings: Decodable {
        let promptN: Int
        let predictedN: Int
    }

    let page: String
    let lines: [Line]
    let timings: Timings
}

// MARK: - What a run writes down

struct ComparisonRun: Codable {
    struct Line: Codable {
        var n: Int
        var ja: String
        var zh: String?
        var compared: String?
        var isEqual: Bool
    }

    struct Page: Codable {
        var page: String
        var requests: Int
        var promptTokens: Int
        var comparedPromptTokens: Int
        var sourceTokens: Int
        var generatedTokens: Int
        var comparedGeneratedTokens: Int
        var finish: String
        var promptSeconds: Double
        var generationSeconds: Double
        var wallSeconds: Double
        /// The machine's one-minute load average when the page started.
        var loadAverage: Double
        var answer: String
        var lines: [Line]

        init(_ compared: ComparedRunPage, result: LanguageModelPage, wall: Double, load: Double) {
            let generations = result.requests.map(\.generation)
            page = compared.page
            requests = result.requests.count
            promptTokens = generations.map(\.promptTokens).reduce(0, +)
            comparedPromptTokens = compared.timings.promptN
            sourceTokens = result.requests.map(\.sourceTokens).reduce(0, +)
            generatedTokens = generations.map(\.generatedTokens).reduce(0, +)
            comparedGeneratedTokens = compared.timings.predictedN
            finish = generations.map { "\($0.finish)" }.joined(separator: ",")
            promptSeconds = generations.map(\.promptDuration.seconds).reduce(0, +)
            generationSeconds = generations.map(\.generationDuration.seconds).reduce(0, +)
            wallSeconds = wall
            loadAverage = load
            answer = generations.map(\.text).joined(separator: "\n----\n")
            lines = zip(compared.lines, result.lines).map { line, translation in
                Line(n: line.n, ja: line.ja, zh: translation, compared: line.zh, isEqual: translation == line.zh)
            }
        }
    }

    var model: String
    var file: String
    var modelSummary = ""
    var contextLength = 0
    var device = ""
    var systemInfo = ""
    var loadSeconds = 0.0
    var pages: [Page] = []

    init(model: String, file: String) {
        self.model = model
        self.file = file
    }

    static func read(_ url: URL) throws -> ComparisonRun {
        try JSONDecoder().decode(ComparisonRun.self, from: Data(contentsOf: url))
    }

    func write(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(self).write(to: url, options: .atomic)
    }

    static func loadAverage() -> Double {
        var loads = [Double](repeating: 0, count: 3)
        return getloadavg(&loads, 3) > 0 ? loads[0] : -1
    }

    var summary: String {
        let lines = pages.flatMap(\.lines)
        let back = lines.count { $0.zh != nil }
        let equal = lines.count(where: \.isEqual)
        let generated = pages.map(\.generatedTokens).reduce(0, +)
        let prompt = pages.map(\.promptTokens).reduce(0, +)
        let generationSeconds = pages.map(\.generationSeconds).reduce(0, +)
        let promptSeconds = pages.map(\.promptSeconds).reduce(0, +)
        let loads = pages.map(\.loadAverage)
        return """
        Language-model comparison, \(model) (\(modelSummary), \(device), context \(contextLength)):
          lines back \(back) of \(lines.count), equal to the compared run \(equal), different \(lines.count - equal)
          \(String(format: "%.0f", pages.map(\.wallSeconds).reduce(0, +))) s for \(pages.count) pages; \
        \(generated) tokens generated at \(String(format: "%.1f", Double(generated) / max(generationSeconds, 0.001))) a second, \
        \(prompt) prompt tokens at \(String(format: "%.1f", Double(prompt) / max(promptSeconds, 0.001))) a second
          load \(String(format: "%.0f", loads.min() ?? 0)) to \(String(format: "%.0f", loads.max() ?? 0)), \
        model loaded in \(String(format: "%.1f", loadSeconds)) s
        """
    }
}

extension Duration {
    var seconds: Double {
        Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}
