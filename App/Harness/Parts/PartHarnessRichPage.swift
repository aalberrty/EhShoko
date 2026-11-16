#if DEBUG || HARNESS
import Dependencies
import EhCore
import EhDatabase
import EhModels
import Foundation

/// The fuller stored page of the harness's first gallery (`-HarnessRich YES`), for walking a
/// gallery page offline: both titles, an archive link, 58 tags in eight namespaces (one voted
/// up, one weak), six comments (the uploader's, a long one, a negative score and one of the
/// user's own), 40 previews and stored tag translations with details. Tags are translated in
/// the harness's settings, so chips show the translations.
///
/// | Argument | Meaning |
/// |---|---|
/// | `-HarnessRich YES` | This page instead of the plain one. |
/// | `-HarnessFavorited YES` | The page says the gallery is a favourite. |
/// | `-HarnessRated <half stars>` | The user's own rating, 1 to 10. |
/// | `-HarnessPages <n>` | The page count, 48 by default. |
/// | `-HarnessProgress <page>` | The page last read, 23 by default; 0 for none. |
enum PartHarnessRichPage {
    static let isRequested = UserDefaults.standard.bool(forKey: "HarnessRich")

    /// Stores the page and its translations in the harness's database, then reads the
    /// translations in.
    static func seed(_ gallery: Gallery, covers: [URL]) async {
        @Dependency(\.database) var database
        @Dependency(\.tagTranslationService) var translations
        let defaults = UserDefaults.standard
        let pages = defaults.integer(forKey: "HarnessPages") > 0 ? defaults.integer(forKey: "HarnessPages") : 48
        let progress = defaults.object(forKey: "HarnessProgress") == nil ? 23 : defaults.integer(forKey: "HarnessProgress")
        let detail = GalleryDetail(
            gid: gallery.gid,
            title: "(C103) [Mizuiro Atelier (Hoshino Kanae)] Yoake no Hakoniwa ~Garden at Daybreak~ (Original) [English] [Digital]",
            jpnTitle: "(C103) [水色アトリエ (星野かなえ)] 夜明けの箱庭 (オリジナル) [英訳] [DL版]",
            isFavorited: defaults.bool(forKey: "HarnessFavorited"), visibility: .yes,
            rating: 4.72, userRating: Float(defaults.integer(forKey: "HarnessRated")) / 2, ratingCount: 318,
            category: .doujinshi, language: .english, uploader: uploader, postedDate: gallery.postedDate,
            coverURL: gallery.coverURL, archiveURL: URL(string: "https://e-hentai.org/archiver.php?gid=\(gallery.gid)"),
            favoritedCount: 2_941, pageCount: pages, sizeCount: 86.4, sizeType: "MB", torrentCount: 3
        )
        var previews: [Int: URL] = [:]
        for page in 1...min(pages, 40) where !covers.isEmpty {
            previews[page] = covers[(page * 7) % covers.count]
        }
        let state = GalleryState(gid: gallery.gid, tags: tags, previewURLs: previews, comments: comments(after: gallery.postedDate))
        try? await database.saveDetail(detail, state: state)
        if progress > 0 {
            try? await database.updateReadingProgress(gid: gallery.gid, progress: progress)
        }
        try? await database.replaceTagTranslations(storedTranslations)
        await translations.load()
    }

    private static let uploader = "lantern_scans"

    private static let tags: [GalleryTag] = {
        func tag(_ namespace: String, _ texts: [String]) -> GalleryTag {
            GalleryTag(rawNamespace: namespace, contents: texts.enumerated().map { index, text in
                GalleryTag.Content(
                    rawNamespace: namespace, text: text, isVotedUp: namespace == "female" && index == 1,
                    isVotedDown: false, backgroundColor: nil, isWeak: namespace == "female" && index == 7
                )
            })
        }
        let female = [
            "sole female", "glasses", "kimono", "ponytail", "stockings", "twintails", "school uniform", "swimsuit",
            "maid", "nurse", "kemonomimi", "dark skin", "bunny girl", "pantyhose", "elf", "tomboy", "big breasts",
            "smell", "very long tag name that goes on and on", "hair bun", "mole", "freckles", "gyaru", "tanlines",
            "apron", "leotard", "thigh high boots", "garter belt", "choker", "eyepatch",
        ]
        return [
            tag("language", ["english", "translated"]),
            tag("parody", ["original"]),
            tag("character", ["reimu hakurei", "marisa kirisame", "shimakaze"]),
            tag("group", ["mizuiro atelier"]),
            tag("artist", ["hoshino kanae"]),
            tag("female", female),
            tag("male", ["sole male", "glasses", "muscle", "bald", "tall man", "dark skin", "shotacon", "beard", "scar"]),
            tag("other", [
                "full color", "story arc", "multi-work series", "uncensored", "webtoon", "mosaic censorship",
                "anthology", "tankoubon", "variant set", "artbook", "rough translation",
            ]),
        ]
    }()

    private static func comments(after posted: Date) -> [GalleryComment] {
        func comment(_ id: String, _ author: String, _ score: String?, _ text: String, up: Bool = false) -> GalleryComment {
            GalleryComment(
                votedUp: up, votedDown: false, votable: id != "0", editable: id == "4", score: score, author: author,
                contents: [CommentContent(type: .plainText, text: text)], commentID: id,
                commentDate: posted.addingTimeInterval(Double(Int(id) ?? 0) * 4_200)
            )
        }
        return [
            // The site gives the uploader's comment the id 0 and no score.
            comment("0", uploader, nil, "Scanned from my own copy at 600 dpi. The sequel is on the way: https://e-hentai.org/g/3000017/abcdef0123/"),
            comment("1", "kagerou", "+42", "Wonderful line work again. The garden chapter is the best one in the whole series, and the translation reads naturally."),
            comment("2", "mmmmmmmmmmmmmmmmmmmm", "+7", "Thanks for the upload!", up: true),
            comment("3", "zwarte", "-3", "Page 12 is out of order."),
            comment("4", "tester", "+1", "A comment of my own, which I can edit."),
            comment("5", "nekomimi", "+15", "次の巻が楽しみです。翻訳ありがとうございます。"),
        ]
    }

    /// Translations of a few of the tags, two with a description for the tag's details.
    private static let storedTranslations: [StoredTagTranslation] = translationTable.map { namespace, key, value, description in
        StoredTagTranslation(
            key: namespace.rawValue + key,
            translation: TagTranslation(namespace: namespace, key: key, value: value, description: description),
            displayValue: value, valueImageURL: nil
        )
    }

    private static let translationTable: [(TagNamespace, String, String, String?)] = [
        (.female, "glasses", "眼镜", "Wearing spectacles of any shape. Sunglasses and goggles have their own tags."),
        (.female, "kimono", "和服", "A traditional Japanese garment."),
        (.female, "ponytail", "马尾", nil), (.female, "stockings", "长筒袜", nil), (.female, "twintails", "双马尾", nil),
        (.female, "sole female", "单女主", nil), (.male, "sole male", "单男主", nil),
        (.language, "english", "英语", nil), (.language, "translated", "翻译", nil),
        (.parody, "original", "原创", nil), (.other, "full color", "全彩", nil),
    ]
}
#endif
