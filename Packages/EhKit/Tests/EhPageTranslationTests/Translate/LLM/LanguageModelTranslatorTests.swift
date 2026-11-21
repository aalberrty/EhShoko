import EhModels
@testable import EhPageTranslation
import Foundation
import Testing

@Suite struct LanguageModelTranslatorTests {
    private func translator(
        _ choice: TranslatorChoice = .galTransl4B, engine: StubGenerationEngine
    ) throws -> LanguageModelTranslator {
        LanguageModelTranslator(profile: try #require(LanguageModelProfile(choice)), engine: engine)
    }

    // MARK: One request

    @Test(arguments: [TranslatorChoice.galTransl4B, .sakura1_5B, .hyMT2, .qwen35_4B])
    func theWholePageGoesToTheModelInOneRequestWithItsPromptAndSampling(choice: TranslatorChoice) async throws {
        let engine = StubGenerationEngine(answer: "1: 你好\n2: 老师")
        let profile = try #require(LanguageModelProfile(choice))
        let results = try await translator(choice, engine: engine).translate(["こんにちは", "先生"])
        #expect(results == ["你好", "老师"])
        #expect(engine.calls == [
            .init(
                prompt: profile.prompt.text(for: ["こんにちは", "先生"]),
                options: TextGenerationOptions(maxTokens: 400, sampling: profile.sampling)
            )
        ])
    }

    @Test func aLineMissingFromTheAnswerIsNilAndTheOthersKeepTheirPlaces() async throws {
        let engine = StubGenerationEngine(answer: "3: 哎呀\n1: 你好\n7: 多余")
        let results = try await translator(engine: engine).translate(["こんにちは", "先生", "ひぇ", "あれ"])
        #expect(results == ["你好", nil, "哎呀", nil])
    }

    @Test func blankLinesAreNotSentAndTheNumbersSkipThem() async throws {
        let engine = StubGenerationEngine.echoing()
        let results = try await translator(engine: engine).translate(["あ", "  ", "い", "", "う"])
        #expect(results == ["译あ", nil, "译い", nil, "译う"])
        #expect(engine.prompts.count == 1)
        #expect(engine.prompts[0].contains("\n1: あ\n2: い\n3: う<|im_end|>"))
    }

    @Test func aPageWithNothingToTranslateAsksTheModelNothing() async throws {
        let engine = StubGenerationEngine.echoing()
        let translator = try translator(engine: engine)
        #expect(try await translator.translate([]).isEmpty)
        #expect(try await translator.translate([" ", "\n"]) == [nil, nil])
        #expect(engine.calls.isEmpty)
    }

    /// The limit may have cut the last line in the middle; a model that ended on its own did
    /// not.
    @Test(arguments: [TextGeneration.Finish.tokenLimit, .contextFull])
    func anAnswerThatRanIntoALimitLosesItsLastLine(finish: TextGeneration.Finish) async throws {
        let engine = StubGenerationEngine(.answer { _, _ in ("1: 你好\n2: 老师\n3: 是啊，管", finish) })
        let results = try await translator(engine: engine).translate(["こんにちは", "先生", "そうだな執事"])
        #expect(results == ["你好", "老师", nil])
    }

    @Test func anErrorOfTheEngineIsThrownOn() async throws {
        let translator = try translator(engine: StubGenerationEngine(.fail(StubEngineError())))
        await #expect(throws: StubEngineError()) { try await translator.translate(["あ"]) }
    }

    @Test func theRecordSaysWhatWasAskedAndAnswered() async throws {
        let engine = StubGenerationEngine.echoing()
        let page = try await translator(engine: engine).translateRecording(["あ", " ", "い"])
        #expect(page.lines == ["译あ", nil, "译い"])
        let request = try #require(page.requests.first)
        #expect(page.requests.count == 1)
        #expect(request.lineIndices == [0, 2])
        #expect(request.prompt == engine.prompts[0])
        #expect(request.sourceTokens == "1: あ\n2: い".count)
        #expect(request.generation.text == "1: 译あ\n2: 译い")
        #expect(request.generation.finish == .endOfGeneration)
    }

    // MARK: A page that does not fit

    /// A context in which the prompt of `fitting` lines of ten characters leaves just enough
    /// room for their answer, and that of one line more does not.
    private func context(fitting count: Int, lines: [String]) throws -> Int {
        let profile = try #require(LanguageModelProfile(.galTransl4B))
        let source = Array(lines.prefix(count))
        let reserve = LanguageModelProfile.answerReserve(sourceTokens: NumberedLines.text(source).count)
        return profile.prompt.text(for: source).count + reserve
    }

    private static let tenLines = (0..<10).map { "これは行\($0)のせりふです" }

    @Test func aPageThatFitsIsNotSplit() async throws {
        let engine = StubGenerationEngine.echoing(contextLength: try context(fitting: 10, lines: Self.tenLines))
        let results = try await translator(engine: engine).translate(Self.tenLines)
        #expect(results == Self.tenLines.map { "译\($0)" })
        #expect(engine.calls.count == 1)
    }

    @Test func aPageThatDoesNotFitIsAskedForInTwoHalvesEachNumberedFromOne() async throws {
        let engine = StubGenerationEngine.echoing(contextLength: try context(fitting: 9, lines: Self.tenLines))
        let page = try await translator(engine: engine).translateRecording(Self.tenLines)
        #expect(page.lines == Self.tenLines.map { "译\($0)" })
        #expect(page.requests.map(\.lineIndices) == [[0, 1, 2, 3, 4], [5, 6, 7, 8, 9]])
        #expect(engine.prompts.count == 2)
        #expect(StubGenerationEngine.numberedLines(in: engine.prompts[0]).map(\.number) == [1, 2, 3, 4, 5])
        #expect(StubGenerationEngine.numberedLines(in: engine.prompts[1]).map(\.number) == [1, 2, 3, 4, 5])
        #expect(StubGenerationEngine.numberedLines(in: engine.prompts[1]).first?.text == Self.tenLines[5])
    }

    @Test func theFirstHalfOfAnOddPageIsTheLargerOne() async throws {
        let lines = Array(Self.tenLines.prefix(7))
        let engine = StubGenerationEngine.echoing(contextLength: try context(fitting: 6, lines: lines))
        let page = try await translator(engine: engine).translateRecording(lines)
        #expect(page.lines == lines.map { "译\($0)" })
        #expect(page.requests.map(\.lineIndices) == [[0, 1, 2, 3], [4, 5, 6]])
    }

    @Test func aHalfThatDoesNotFitIsSplitAgain() async throws {
        let engine = StubGenerationEngine.echoing(contextLength: try context(fitting: 3, lines: Self.tenLines))
        let page = try await translator(engine: engine).translateRecording(Self.tenLines)
        #expect(page.lines == Self.tenLines.map { "译\($0)" })
        #expect(page.requests.map(\.lineIndices) == [[0, 1, 2], [3, 4], [5, 6, 7], [8, 9]])
    }

    @Test func aPageIsAlsoSplitWhenItsAnswerWouldPassTheTokenLimit() async throws {
        var profile = try #require(LanguageModelProfile(.galTransl4B))
        // Room for the answer to five of the lines, in a context that would hold them all.
        profile.maxTokens = LanguageModelProfile.answerReserve(
            sourceTokens: NumberedLines.text(Array(Self.tenLines.prefix(5))).count
        )
        let engine = StubGenerationEngine.echoing(contextLength: 100_000)
        let page = try await LanguageModelTranslator(profile: profile, engine: engine).translateRecording(Self.tenLines)
        #expect(page.lines == Self.tenLines.map { "译\($0)" })
        #expect(page.requests.map(\.lineIndices) == [[0, 1, 2, 3, 4], [5, 6, 7, 8, 9]])
        #expect(engine.calls.allSatisfy { $0.options.maxTokens == profile.maxTokens })
    }

    /// A line too long for the model even alone stays as it is, and the others are translated.
    @Test func aLineThatFitsNoRequestIsNil() async throws {
        let long = String(repeating: "長", count: 400)
        let lines = ["あ", long, "い"]
        let engine = StubGenerationEngine.echoing(contextLength: try context(fitting: 1, lines: ["あいうえおかきくけこ"]))
        let page = try await translator(engine: engine).translateRecording(lines)
        #expect(page.lines == ["译あ", nil, "译い"])
        #expect(page.requests.map(\.lineIndices) == [[0], [2]])
        #expect(engine.prompts.allSatisfy { !$0.contains(long) })
    }

    // MARK: Stopping

    @Test func aTaskCancelledBeforehandAsksTheModelNothing() async throws {
        let engine = StubGenerationEngine.echoing()
        let translator = try translator(engine: engine)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await translator.translate(["あ", "い"])
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(engine.calls.isEmpty)
    }

    /// The engine returns what it had when the task was cancelled. That is half a page, so it
    /// is not returned.
    @Test func cancellingTheTaskWhileTheModelGeneratesThrowsAndReturnsNoPartOfThePage() async throws {
        let engine = StubGenerationEngine(.untilStopped(partial: "1: 你好\n2: 老"))
        let translator = try translator(engine: engine)
        let task = Task { try await translator.translate(["こんにちは", "先生"]) }
        await engine.waitForCalls()
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(engine.calls.count == 1)
    }

    @Test func stopEndsThePageInWorkWithoutItsTaskBeingCancelled() async throws {
        let engine = StubGenerationEngine(.untilStopped(partial: "1: 你好\n2: 老"))
        let translator = try translator(engine: engine)
        let task = Task { try await translator.translate(["こんにちは", "先生"]) }
        await engine.waitForCalls()
        translator.stop()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(engine.stopCount == 1)
        #expect(!task.isCancelled)
    }

    /// A page in two halves is given up between them: the second is never asked for.
    @Test func aPageCancelledAfterItsFirstHalfDoesNotAskForTheSecond() async throws {
        let contextLength = try context(fitting: 9, lines: Self.tenLines)
        let engine = StubGenerationEngine(contextLength: contextLength, .answer { _, _ in
            withUnsafeCurrentTask { $0?.cancel() }
            return ("1: 你好", .endOfGeneration)
        })
        let translator = try translator(engine: engine)
        let task = Task { try await translator.translate(Self.tenLines) }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(engine.calls.count == 1)
    }

    // MARK: The loader

    @Test func theLoaderBuildsTheChoicesTranslatorOnTheEngineItIsGiven() async throws {
        let engine = StubGenerationEngine(answer: "1: 你好")
        let loader = PageTranslatorLoader(languageModel: PageTranslatorLoader.languageModelLoader { file, profile in
            #expect(file.lastPathComponent == "model.gguf")
            #expect(profile == LanguageModelProfile(.sakura1_5B))
            return engine
        })
        let translator = try await loader.load(.sakura1_5B, from: URL(filePath: "/models/model.gguf"))
        #expect((translator as? LanguageModelTranslator)?.profile.prompt == .sakura)
        #expect(try await translator.translate(["こんにちは"]) == ["你好"])
        #expect(engine.prompts == [LanguageModelPrompt.sakura.text(for: ["こんにちは"])])
    }

    @Test func theLoaderHasNoLanguageModelForTheCoreMLChoice() async {
        let load = PageTranslatorLoader.languageModelLoader { _, _ in StubGenerationEngine(answer: "") }
        await #expect(throws: PageTranslatorError.unavailable(.jmtFast1)) {
            _ = try await load(.jmtFast1, URL(filePath: "/models/model.gguf"))
        }
    }
}
