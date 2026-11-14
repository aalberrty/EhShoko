import EhModels
import Testing

@Suite struct ParsedTitleTests {
    /// Real titles from the list fixtures and the parts a row shows from them.
    struct Case: Sendable, CustomTestStringConvertible {
        let raw: String
        let expected: ParsedTitle

        var testDescription: String { raw }
    }

    static let realTitles: [Case] = [
        Case(
            raw: "(C102) [よねや (俵太)] ヴァジぱら!3 (グランブルーファンタジー) [中国翻訳]",
            expected: ParsedTitle(
                core: "ヴァジぱら!3", event: "C102", circle: "よねや", artists: ["俵太"],
                parody: "グランブルーファンタジー", language: "中国翻訳"
            )
        ),
        Case(
            raw: "(C102)[星霜待機 (新川豊一)] 神隷競売 -slave goddesses auction- [DL版]",
            expected: ParsedTitle(
                core: "神隷競売 -slave goddesses auction-", event: "C102", circle: "星霜待機",
                artists: ["新川豊一"], flags: ["DL版"]
            )
        ),
        Case(
            raw: "(C88) [環屋 (よろず)] MILF of STEEL RETURNS (ウチのムスメに手を出すな!) [英訳] [ページ欠落]",
            expected: ParsedTitle(
                core: "MILF of STEEL RETURNS", event: "C88", circle: "環屋", artists: ["よろず"],
                parody: "ウチのムスメに手を出すな!", language: "英訳", flags: ["ページ欠落"]
            )
        ),
        Case(
            // A parenthesis inside the title stays in it.
            raw: "(C91) [不可不可 (関谷あさみ)] クレバーED漫画(仮)プレ版 (クオリディア・コード) [ロシア翻訳]",
            expected: ParsedTitle(
                core: "クレバーED漫画(仮)プレ版", event: "C91", circle: "不可不可", artists: ["関谷あさみ"],
                parody: "クオリディア・コード", language: "ロシア翻訳"
            )
        ),
        Case(
            raw: "(COMIC1☆11) [KAMINENDO.CORP (あかざわRED)] まことに ざんねんですが ぼうけんのしょ1は消えてしまいました。 [中国翻訳]",
            expected: ParsedTitle(
                core: "まことに ざんねんですが ぼうけんのしょ1は消えてしまいました。", event: "COMIC1☆11",
                circle: "KAMINENDO.CORP", artists: ["あかざわRED"], language: "中国翻訳"
            )
        ),
        Case(
            raw: "[Fatalpulse (朝凪)] VictimGirls19 JEZEBEL AMAZONES (ダンジョンに出会いを求めるのは間違っているだろうか)  [カラー化] [無修正] [DL版] [韓国翻訳]",
            expected: ParsedTitle(
                core: "VictimGirls19 JEZEBEL AMAZONES", circle: "Fatalpulse", artists: ["朝凪"],
                parody: "ダンジョンに出会いを求めるのは間違っているだろうか", language: "韓国翻訳",
                flags: ["カラー化", "無修正", "DL版"]
            )
        ),
        Case(
            raw: "[Hinahara Emi] Himetomo [Chinese][两面包夹汉化组]",
            expected: ParsedTitle(
                core: "Himetomo", artists: ["Hinahara Emi"], language: "Chinese", translator: "两面包夹汉化组"
            )
        ),
        Case(
            raw: "[UNAGIMARU] Pizza & Beard [English] {2d-market.com} [Decensored] [Digital]",
            expected: ParsedTitle(
                core: "Pizza & Beard", artists: ["UNAGIMARU"], language: "English", translator: "2d-market.com",
                flags: ["Decensored", "Digital"]
            )
        ),
        Case(
            raw: "[ヤドクガエル、新生フロンティア (ヤドクガエル、kozi)] 弓道男子4配信調教～部活の先輩に秘密撮影会を開かれちゃいました～ [中国翻訳]",
            expected: ParsedTitle(
                core: "弓道男子4配信調教～部活の先輩に秘密撮影会を開かれちゃいました～",
                circle: "ヤドクガエル、新生フロンティア", artists: ["ヤドクガエル", "kozi"], language: "中国翻訳"
            )
        ),
        Case(
            raw: "[StilettoPink, Watsup, Aya Yanagisawa, Allsass] Pothead ReAdventures HD (Ongoing)",
            expected: ParsedTitle(
                core: "Pothead ReAdventures HD", artists: ["StilettoPink", "Watsup", "Aya Yanagisawa", "Allsass"],
                flags: ["Ongoing"]
            )
        ),
        Case(
            // No space before the groups, a parenthesised language after the parody.
            raw: "[merkonig]Alpha wa maketa!(kage no jitsuryokusha ni naritakute!)[Chinese]",
            expected: ParsedTitle(
                core: "Alpha wa maketa!", artists: ["merkonig"], parody: "kage no jitsuryokusha ni naritakute!",
                language: "Chinese"
            )
        ),
        Case(
            raw: "[Marmalade Mum] Chemistry Class 2 (ongoing) (English)",
            expected: ParsedTitle(
                core: "Chemistry Class 2", artists: ["Marmalade Mum"], language: "English", flags: ["ongoing"]
            )
        ),
        Case(
            // A year in parentheses belongs to the title.
            raw: "[Theterm] Fur just wanna be friend (2023) [English] [Ongoing]",
            expected: ParsedTitle(
                core: "Fur just wanna be friend (2023)", artists: ["Theterm"], language: "English", flags: ["Ongoing"]
            )
        ),
        Case(
            // A part number written onto the title, then the parody.
            raw: "[アヘ丸 (ヘンリーク)] 凛の淫乱奮闘記(前編) (Fate/stay night) [中国翻訳]",
            expected: ParsedTitle(
                core: "凛の淫乱奮闘記(前編)", circle: "アヘ丸", artists: ["ヘンリーク"], parody: "Fate/stay night",
                language: "中国翻訳"
            )
        ),
        Case(
            raw: "[Abo Manten] Older Girlfriend Wants To Do An Axe Kick To My Testicles (Textless / Complete)",
            expected: ParsedTitle(
                core: "Older Girlfriend Wants To Do An Axe Kick To My Testicles", artists: ["Abo Manten"],
                flags: ["Textless", "Complete"]
            )
        ),
        Case(
            raw: "[Shooting Star's (Saku)] - Elf Village",
            expected: ParsedTitle(core: "Elf Village", circle: "Shooting Star's", artists: ["Saku"])
        ),
        Case(
            raw: "[MUK] ゆりか＆みやこ特集① [日本語、英語]",
            expected: ParsedTitle(core: "ゆりか＆みやこ特集①", artists: ["MUK"], language: "日本語、英語")
        ),
        Case(
            // Full-width brackets inside the title are title text.
            raw: "[ヨールキ・パールキ (露々々木もげら)] L教会と異端者一家+【おまけ】 [中国翻訳]",
            expected: ParsedTitle(
                core: "L教会と異端者一家+【おまけ】", circle: "ヨールキ・パールキ", artists: ["露々々木もげら"],
                language: "中国翻訳"
            )
        ),
        Case(
            raw: "(成年コミック) [big.g] 人妻即オチ!人妻専用デリヘルアプリ [無修正] [DL版]",
            expected: ParsedTitle(
                core: "人妻即オチ!人妻専用デリヘルアプリ", event: "成年コミック", artists: ["big.g"],
                flags: ["無修正", "DL版"]
            )
        ),
    ]

    @Test(arguments: realTitles)
    func parsesRealTitles(_ testCase: Case) {
        #expect(TitleParser.parse(testCase.raw) == testCase.expected)
    }

    /// Titles that do not follow the convention show as they are.
    @Test(arguments: [
        // No groups at all.
        "Jewel princess Decensored",
        "成人男性失格なので女の子として再教育を受けて下さい",
        // Groups, but nothing in front of the title.
        "DUMBKOALA - Going Incognito (English)",
        "ガールズフォーム Vol.19 [DL版]",
        // A `|` between two versions of the title.
        "[TheKite] Fallout Unsheltered | 異塵餘生：荒淫避難所  (Fallout)[Ongoing][Chinese][變態浣熊漢化組]",
        "[Pixiv] lolicept | belko (39123643)",
        // Unbalanced or nested brackets.
        "[MUK] LO*IDOM CLASS [日本語]、中国語、英語]",
        "●PIXIV● あかざわRED ([10340]",
        "[A [B]] Title",
        "(C102) [Circle (Artist)] Title [English",
        // Full-width brackets where the groups go.
        "【消毒液汉化】(C102) [NANACAN (ななかまい)] 異世界輪姦～洗脳された聖女は肉便器にジョブチェンジして幸せです～ (オリジナル) [DL版][中国翻訳]",
        "【CH35】suite heaven(FF7 ティファ)",
        "（玉潰し注意）彼女が金的に踵落としをしてくれるようです",
        // Empty groups.
        "[] Title",
        "() [Circle] Title",
        "[Circle] Title []",
        "[Circle] Title ()",
        // Nothing left for the title.
        "(C102) [Circle (Artist)] [English]",
        // A collection source in the credit's place.
        "[Pixiv] 不死千代 (7575)",
        "[FANBOX / Patreon] 梅澤一手",
        "[アーティスト] AnimA",
        // A bracket group after the title that is no language, translator or flag.
        "PUSSYSAGA [Game CG Gallery Rip] [COMPLETE AS OF 3/18/2016]",
        "[Circle] Title [39P]",
        // Brackets inside the title.
        "[Circle] Frog eat fox [Cownugget] PT-BR",
    ])
    func fallsBackToTheRawTitle(_ raw: String) {
        #expect(TitleParser.parse(raw) == ParsedTitle(raw: raw))
    }

    @Test func aLeadingTranslatorBeforeTheEvent() {
        let parsed = TitleParser.parse("[脸肿汉化组] (C97) [Circle (Artist)] Title (Parody) [中国翻訳]")
        #expect(parsed == ParsedTitle(
            core: "Title", event: "C97", circle: "Circle", artists: ["Artist"], parody: "Parody",
            language: "中国翻訳", translator: "脸肿汉化组"
        ))
    }

    @Test func theEmptyTitle() {
        #expect(TitleParser.parse("") == ParsedTitle(raw: ""))
        #expect(TitleParser.parse("   ") == ParsedTitle(raw: "   "))
    }

    // MARK: Languages

    @Test(arguments: [
        ("English", Language.english), ("spanish", .spanish), ("中国翻訳", .chinese), ("中国語", .chinese),
        ("英訳", .english), ("英語", .english), ("韓国翻訳", .korean), ("日本語", .japanese),
        ("ロシア翻訳", .russian), ("ポルトガル翻訳", .portuguese), ("汉化", .chinese),
        ("日本語、英語", .japanese), ("English, Chinese", .english),
    ])
    func languageGroups(_ text: String, _ language: Language) {
        #expect(TitleParser.language(named: text) == language)
    }

    @Test(arguments: ["", "DL版", "Other", "N/A", "Fate/Grand Order", "日本語、DL版", "PT-BR", "ゲーム語"])
    func groupsThatAreNoLanguage(_ text: String) {
        #expect(TitleParser.language(named: text) == nil)
    }

    @Test func everyLanguageHasACodeExceptNone() {
        for language in Language.allCases {
            switch language {
            case .invalid, .other:
                #expect(language.code == nil)
            default:
                #expect(language.code == language.abbreviation)
                #expect(language.code?.allSatisfy { $0.isUppercase } == true)
            }
        }
        #expect(Language.english.code == "EN")
        #expect(Language.chinese.code == "ZH")
        #expect(Language.japanese.code == "JA")
    }
}
