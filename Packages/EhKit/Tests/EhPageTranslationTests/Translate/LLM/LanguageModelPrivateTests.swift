import EhModels
@testable import EhPageTranslation
import Foundation
import Testing

/// One page of the run whose outputs were compared blind: what came back from llama.cpp's
/// server and how it was read.
struct ComparedPage: Decodable {
    struct Line: Decodable {
        let n: Int
        let ja: String
        let zh: String?
    }

    let page: String
    let responseText: String
    let lines: [Line]

    static func read(_ url: URL) throws -> ComparedPage {
        try decoder.decode(ComparedPage.self, from: Data(contentsOf: url))
    }

    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }
}

/// What was sent to the server for a page of one of the four models.
struct ComparedRequest: Decodable {
    struct Message: Decodable {
        let role: String
        let content: String
    }

    let messages: [Message]
    let temperature: Double
    let topP: Double
    let topK: Int?
    let minP: Double?
    let repeatPenalty: Double?
    let seed: UInt32

    private struct Record: Decodable {
        let request: ComparedRequest
    }

    static func read(_ url: URL) throws -> ComparedRequest {
        try ComparedPage.decoder.decode(Record.self, from: Data(contentsOf: url)).request
    }
}

/// The opt-in tier for the language models' prompts and answers, against the compared run's
/// records. No model runs here: the runs are in `EhCoreTests`, where the engine is.
@Suite(.privateFolder) struct LanguageModelPrivateTests {
    static let compared = "research/mt-h2h/raw"
    static let everyRun = "research/mt-spike/bakeoff/raw"

    static let models: [(choice: TranslatorChoice, folder: String)] = [
        (.galTransl4B, "galtransl-v4-4b"), (.sakura1_5B, "sakura-1.5b"), (.hyMT2, "hy-mt2-1.8b"),
        (.qwen35_4B, "qwen3.5-4b")
    ]

    /// The request's messages inside the model's template, as the server's template engine
    /// put them together.
    private static func rendered(_ request: ComparedRequest, for prompt: LanguageModelPrompt) throws -> String {
        let system = request.messages.first { $0.role == "system" }?.content
        let user = try #require(request.messages.first { $0.role == "user" }?.content)
        switch prompt {
        case .hymt2:
            try #require(system == nil)
            return LanguageModelPrompt.hunyuan(user: user)
        case .galtransl, .sakura:
            return LanguageModelPrompt.chatML(system: try #require(system), user: user)
        case .qwen35:
            return LanguageModelPrompt.chatML(system: try #require(system), user: user) + "<think>\n\n</think>\n\n"
        }
    }

    @Test func eachModelsPromptIsTheComparedRunsOnAllPages() throws {
        let folder = try PrivateFolder.required()
        for model in Self.models {
            let profile = try #require(LanguageModelProfile(model.choice))
            let pages = try folder.files(in: "\(Self.compared)/\(model.folder)", withExtensions: ["json"])
            try #require(pages.count == 18)
            var lines = 0
            for url in pages {
                let page = try ComparedPage.read(url)
                let request = try ComparedRequest.read(url)
                #expect(page.lines.map(\.n) == Array(1...page.lines.count))
                let ours = profile.prompt.text(for: page.lines.map(\.ja))
                #expect(try ours == Self.rendered(request, for: profile.prompt), "\(model.folder) \(page.page)")
                lines += page.lines.count
            }
            #expect(lines == 139)
        }
    }

    /// What a request left out, the server filled in with its defaults: top-k 40 and min-p
    /// 0.05 (its `/props` of that day, kept beside the outputs), and no repeat penalty.
    @Test func eachModelsSamplingIsTheComparedRuns() throws {
        let folder = try PrivateFolder.required()
        for model in Self.models {
            let profile = try #require(LanguageModelProfile(model.choice))
            for url in try folder.files(in: "\(Self.compared)/\(model.folder)", withExtensions: ["json"]) {
                let request = try ComparedRequest.read(url)
                let sampling = TextSampling(
                    temperature: request.temperature, topP: request.topP, topK: request.topK ?? 40,
                    minP: request.minP ?? 0.05, repeatPenalty: request.repeatPenalty ?? 1, seed: request.seed
                )
                #expect(profile.sampling == sampling, "\(model.folder) \(url.lastPathComponent)")
            }
        }
    }

    /// Every answer of the research's runs, the models that were dropped among them, read
    /// here as it was read then: the same line for each number, and the same numbers missing.
    @Test func everyRecordedAnswerIsReadAsItWasRead() throws {
        let folder = try PrivateFolder.required()
        let runs = try FileManager.default.contentsOfDirectory(
            at: folder.url(Self.everyRun), includingPropertiesForKeys: nil
        ).filter(\.hasDirectoryPath)
        try #require(runs.count >= 10)
        var answers = 0
        var missing = 0
        for run in runs {
            for url in try FileManager.default.contentsOfDirectory(at: run, includingPropertiesForKeys: nil)
            where url.pathExtension == "json" {
                let page = try ComparedPage.read(url)
                let read = NumberedLines.parse(page.responseText, count: page.lines.count)
                // An empty translation was kept as an empty text then; here it is no translation.
                let expected = page.lines.map { $0.zh.flatMap { $0.isEmpty ? nil : $0 } }
                #expect(read == expected, "\(run.lastPathComponent) \(page.page)")
                answers += 1
                missing += expected.count { $0 == nil }
            }
        }
        #expect(answers >= 180)
        print("LanguageModelPrivateTests: \(answers) recorded answers read alike, \(missing) lines missing in them")
    }
}
