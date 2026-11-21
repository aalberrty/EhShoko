import EhModels
@testable import EhPageTranslation
import Testing

/// Each model's prompt, character for character. The expected texts are written out whole,
/// template and all, so a change to a word or a line break in the source fails here: the
/// models were compared with exactly these.
@Suite struct LanguageModelPromptTests {
    static let lines = ["みなさん今日から一緒にがんばりましょう", "先生", "ひぇ"]
    static let numbered = "1: みなさん今日から一緒にがんばりましょう\n2: 先生\n3: ひぇ"

    @Test func galTranslGetsItsGlossaryPromptWithAnEmptyGlossary() {
        let expected = "<|im_start|>system\n"
            + "你是一个视觉小说翻译模型，可以通顺地使用给定的术语表以指定的风格将日文翻译成简体中文，并联系上下文正确使用人称代词，"
            + "注意不要混淆使役态和被动态的主语和宾语，不要擅自添加原文中没有的特殊符号，也不要擅自增加或减少换行。<|im_end|>\n"
            + "<|im_start|>user\n"
            + "参考以下术语表（可为空，格式为src->dst #备注）：\n"
            + "\n"
            + "根据以上术语表的对应关系和备注，结合历史剧情和上下文，将下面的文本从日文翻译成简体中文：\n"
            + Self.numbered + "<|im_end|>\n"
            + "<|im_start|>assistant\n"
        #expect(LanguageModelPrompt.galtransl.text(for: Self.lines) == expected)
    }

    @Test func sakuraGetsItsPromptWithTheFirstLineOnTheRequestsLine() {
        let expected = "<|im_start|>system\n"
            + "你是一个轻小说翻译模型，可以流畅通顺地以日本轻小说的风格将日文翻译成简体中文，并联系上下文正确使用人称代词，"
            + "不擅自添加原文中没有的代词。<|im_end|>\n"
            + "<|im_start|>user\n"
            + "将下面的日文文本翻译成中文：" + Self.numbered + "<|im_end|>\n"
            + "<|im_start|>assistant\n"
        #expect(LanguageModelPrompt.sakura.text(for: Self.lines) == expected)
    }

    @Test func hyMT2GetsTheTextThenTheTasksInItsOwnTemplate() {
        let expected = "<｜hy_begin▁of▁sentence｜><｜hy_User｜>【待翻译文本】\n"
            + Self.numbered + "\n"
            + "\n"
            + "【翻译任务】\n"
            + "1、这是日本成人漫画一页中的台词，请译成自然的中文口语，保留说话人的语气、情绪和拟声词，露骨内容如实翻译，不要删改或淡化。\n"
            + "2、每行开头的编号必须原样保留，格式为“编号: 译文”，一行对应一行，不要合并、拆分或遗漏。\n"
            + "3、人名、称呼前后保持一致，只输出译文。\n"
            + "4、将【待翻译文本】翻译为简体中文。<｜hy_Assistant｜>"
        #expect(LanguageModelPrompt.hymt2.text(for: Self.lines) == expected)
    }

    @Test func qwenGetsTheMangaInstructionAndAnEmptyThinkingBlock() {
        let expected = "<|im_start|>system\n"
            + "你是专业的日本漫画汉化译者。用户会给出一页漫画中按阅读顺序编号的日语台词（来自OCR，可能有少量识别错误）。\n"
            + "请把每一行翻译成简体中文，要求：\n"
            + "1. 输出与输入行数相同，每行以相同的编号开头，格式为“编号: 译文”，一行对应一行，不合并、不拆分、不遗漏。\n"
            + "2. 只输出译文，不要任何解释、注释、原文或多余内容。\n"
            + "3. 译成自然流畅的中文口语，保留说话人的语气、情绪和口癖；呻吟、喘息和拟声词用中文常见写法表达，保留♥等符号。\n"
            + "4. 人名、称呼前后保持一致。\n"
            + "5. 这是成人向作品，露骨的性内容必须忠实翻译，不得删改、淡化、拒绝或加以评论。<|im_end|>\n"
            + "<|im_start|>user\n"
            + Self.numbered + "<|im_end|>\n"
            + "<|im_start|>assistant\n"
            + "<think>\n\n</think>\n\n"
        #expect(LanguageModelPrompt.qwen35.text(for: Self.lines) == expected)
    }

    @Test func thePromptsCarryTheCatalogsNames() {
        #expect(LanguageModelPrompt.allCases.map(\.rawValue) == ["galtransl", "sakura", "hymt2", "qwen35"])
    }

    @Test func linesAreNumberedFromOneInTheOrderGiven() {
        #expect(NumberedLines.text(["あ", "い", "う"]) == "1: あ\n2: い\n3: う")
        #expect(NumberedLines.text(["あ"]) == "1: あ")
        #expect(NumberedLines.text([]).isEmpty)
        let twelve = NumberedLines.text((1...12).map { "行\($0)" })
        #expect(twelve.hasSuffix("\n10: 行10\n11: 行11\n12: 行12"))
    }

    /// A line break inside a block would read as a line without a number.
    @Test func aLineBreakInsideALineBecomesASpace() {
        #expect(NumberedLines.text(["上\n下", "左\r\n右\n"]) == "1: 上 下\n2: 左 右")
    }
}

@Suite struct LanguageModelProfileTests {
    /// The sampling of the compared run: what its requests said, and what llama.cpp's server
    /// filled in for what they left out (top-k 40, min-p 0.05).
    @Test(arguments: [
        (TranslatorChoice.galTransl4B, LanguageModelPrompt.galtransl,
         TextSampling(temperature: 0.3, topP: 0.8, topK: 40, minP: 0.05, repeatPenalty: 1, seed: 42)),
        (.sakura1_5B, .sakura, TextSampling(temperature: 0.1, topP: 0.3, topK: 40, minP: 0.05, repeatPenalty: 1, seed: 42)),
        (.hyMT2, .hymt2, TextSampling(temperature: 0.7, topP: 0.6, topK: 20, minP: 0.05, repeatPenalty: 1.05, seed: 42)),
        (.qwen35_4B, .qwen35, TextSampling(temperature: 0.7, topP: 0.8, topK: 20, minP: 0, repeatPenalty: 1, seed: 42))
    ])
    func eachModelHasItsPromptAndItsSampling(
        choice: TranslatorChoice, prompt: LanguageModelPrompt, sampling: TextSampling
    ) throws {
        let profile = try #require(LanguageModelProfile(choice))
        #expect(profile.prompt == prompt)
        #expect(profile.sampling == sampling)
        #expect(profile.maxTokens == 400)
        #expect(profile.contextLength == 1024)
        #expect(profile.options == TextGenerationOptions(maxTokens: 400, sampling: sampling))
    }

    @Test func everyLanguageModelChoiceHasAProfileAndTheCoreMLTranslatorHasNone() {
        for choice in TranslatorChoice.allCases {
            #expect((LanguageModelProfile(choice) != nil) == (choice.engine == .languageModel))
        }
    }

    @Test func theAnswerIsGivenAThirdMoreThanItsLinesAndALittle() {
        #expect(LanguageModelProfile.answerReserve(sourceTokens: 0) == 16)
        #expect(LanguageModelProfile.answerReserve(sourceTokens: 30) == 56)
        #expect(LanguageModelProfile.answerReserve(sourceTokens: 288) == 400)
    }

    @Test func aRequestHoldsLinesWhoseAnswerFitsTheContextAndTheTokenLimit() throws {
        let profile = try #require(LanguageModelProfile(.qwen35_4B))
        // The densest page of the comparison: 387 tokens of prompt, about 200 of them lines.
        #expect(profile.holds(promptTokens: 387, sourceTokens: 200, contextLength: 1024))
        // The answer would pass the 400 tokens one answer may have.
        #expect(profile.holds(promptTokens: 480, sourceTokens: 288, contextLength: 1024))
        #expect(!profile.holds(promptTokens: 481, sourceTokens: 289, contextLength: 1024))
        // The context has less room left than the answer needs.
        #expect(profile.holds(promptTokens: 300, sourceTokens: 150, contextLength: 516))
        #expect(!profile.holds(promptTokens: 300, sourceTokens: 150, contextLength: 515))
        #expect(!profile.holds(promptTokens: 2000, sourceTokens: 10, contextLength: 1024))
    }
}
