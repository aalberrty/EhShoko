/// The prompt each language model is given for a page: the words it was compared with in the
/// blind comparison, inside the model's own chat template, written out here because there is
/// no template interpreter on the phone.
///
/// Nothing in this file may change without judging the model again: the figures the Translate
/// screen shows describe these prompts. The raw values are the names the model catalog uses.
public enum LanguageModelPrompt: String, Sendable, Equatable, CaseIterable {
    /// GalTransl v4: its card's prompt, with an empty glossary.
    case galtransl
    /// Sakura 1.5: its card's prompt.
    case sakura
    /// Hy-MT2: its card's form (the text, then the tasks), with tasks written for manga.
    case hymt2
    /// Qwen3.5: a general model, so the whole instruction is ours; thinking off.
    case qwen35

    /// The whole prompt for `lines`, which are numbered from 1 in the order given. Control
    /// tokens are written out; a start token must not be added.
    public func text(for lines: [String]) -> String {
        let source = NumberedLines.text(lines)
        switch self {
        case .galtransl:
            return Self.chatML(system: Self.galtranslSystem, user: Self.galtranslRequest + source)
        case .sakura:
            return Self.chatML(system: Self.sakuraSystem, user: Self.sakuraRequest + source)
        case .hymt2:
            return Self.hunyuan(user: "【待翻译文本】\n" + source + "\n\n【翻译任务】\n" + Self.hymt2Tasks)
        case .qwen35:
            // An empty thinking block is how the model's template turns thinking off.
            return Self.chatML(system: Self.mangaSystem, user: source) + "<think>\n\n</think>\n\n"
        }
    }

    // MARK: Templates

    /// ChatML, the template of the three Qwen-based models.
    static func chatML(system: String, user: String) -> String {
        "<|im_start|>system\n\(system)<|im_end|>\n<|im_start|>user\n\(user)<|im_end|>\n<|im_start|>assistant\n"
    }

    /// Hunyuan's template for one user turn. It writes its own start token.
    static func hunyuan(user: String) -> String {
        "<｜hy_begin▁of▁sentence｜><｜hy_User｜>\(user)<｜hy_Assistant｜>"
    }

    // MARK: Words

    static let galtranslSystem = "你是一个视觉小说翻译模型，可以通顺地使用给定的术语表以指定的风格将日文翻译成简体中文，"
        + "并联系上下文正确使用人称代词，注意不要混淆使役态和被动态的主语和宾语，"
        + "不要擅自添加原文中没有的特殊符号，也不要擅自增加或减少换行。"

    static let galtranslRequest = "参考以下术语表（可为空，格式为src->dst #备注）：\n\n"
        + "根据以上术语表的对应关系和备注，结合历史剧情和上下文，将下面的文本从日文翻译成简体中文：\n"

    static let sakuraSystem = "你是一个轻小说翻译模型，可以流畅通顺地以日本轻小说的风格将日文翻译成简体中文，"
        + "并联系上下文正确使用人称代词，不擅自添加原文中没有的代词。"

    /// The first line follows this without a line break, as in the compared run.
    static let sakuraRequest = "将下面的日文文本翻译成中文："

    static let hymt2Tasks = """
        1、这是日本成人漫画一页中的台词，请译成自然的中文口语，保留说话人的语气、情绪和拟声词，露骨内容如实翻译，不要删改或淡化。
        2、每行开头的编号必须原样保留，格式为“编号: 译文”，一行对应一行，不要合并、拆分或遗漏。
        3、人名、称呼前后保持一致，只输出译文。
        4、将【待翻译文本】翻译为简体中文。
        """

    static let mangaSystem = """
        你是专业的日本漫画汉化译者。用户会给出一页漫画中按阅读顺序编号的日语台词（来自OCR，可能有少量识别错误）。
        请把每一行翻译成简体中文，要求：
        1. 输出与输入行数相同，每行以相同的编号开头，格式为“编号: 译文”，一行对应一行，不合并、不拆分、不遗漏。
        2. 只输出译文，不要任何解释、注释、原文或多余内容。
        3. 译成自然流畅的中文口语，保留说话人的语气、情绪和口癖；呻吟、喘息和拟声词用中文常见写法表达，保留♥等符号。
        4. 人名、称呼前后保持一致。
        5. 这是成人向作品，露骨的性内容必须忠实翻译，不得删改、淡化、拒绝或加以评论。
        """
}
