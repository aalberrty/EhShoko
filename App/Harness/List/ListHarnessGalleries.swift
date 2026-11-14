#if DEBUG
import EhModels
import Foundation

/// The synthetic galleries of the list harness: the same list on every run, shaped like the
/// site's (bracketed circles and languages in titles, one to three title lines, zero to thirty
/// tags, every category), with covers served by `ListHarnessURLProtocol`.
nonisolated enum ListHarnessGalleries {
    /// Built off the main actor; 500 galleries take a few milliseconds.
    @concurrent
    static func make(count: Int, session: String, coverLatency: Double) async -> [Gallery] {
        var generator = SplitMix64(seed: 0xE4_9A_4D_A0)
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        return (0..<count).map { index in
            gallery(index: index, session: session, coverLatency: coverLatency, now: now, using: &generator)
        }
    }

    private static func gallery(
        index: Int, session: String, coverLatency: Double, now: Date, using generator: inout SplitMix64
    ) -> Gallery {
        let gid = String(3_000_000 + index * 17)
        let language = languages.randomElement(using: &generator) ?? "japanese"
        return Gallery(
            gid: gid,
            token: String(format: "%010x", generator.next() & 0xFF_FFFF_FFFF),
            title: title(language: language, using: &generator),
            rating: Float(Int.random(in: 1...10, using: &generator)) / 2,
            tags: tags(language: language, using: &generator),
            category: Category.allCases.filter { $0 != .private }.randomElement(using: &generator) ?? .doujinshi,
            uploader: uploaders.randomElement(using: &generator),
            pageCount: Int.random(in: 1...420, using: &generator),
            postedDate: now.addingTimeInterval(-Double(index) * 1_700 - Double.random(in: 0...1_500, using: &generator)),
            coverURL: ListHarnessURLProtocol.coverURL(index: index, session: session, latency: coverLatency),
            galleryURL: URL(string: "https://\(ListHarnessURLProtocol.host)/g/\(gid)/")
        )
    }

    private static func title(language: String, using generator: inout SplitMix64) -> String {
        var parts: [String] = []
        if Bool.random(using: &generator) {
            let circle = circles.randomElement(using: &generator) ?? "Circle"
            let artist = artists.randomElement(using: &generator) ?? "Artist"
            parts.append("[\(circle) (\(artist))]")
        }
        let wordCount = Int.random(in: 2...14, using: &generator)
        parts.append((0..<wordCount).map { _ in words.randomElement(using: &generator) ?? "Title" }.joined(separator: " "))
        if Int.random(in: 0..<3, using: &generator) == 0 {
            parts.append("(\(parodies.randomElement(using: &generator) ?? "Original"))")
        }
        if language != "japanese" {
            parts.append("[\(language.capitalized)]")
        }
        if Bool.random(using: &generator) {
            parts.append(["[Digital]", "[Decensored]", "[Ongoing]", "[Colorized]"].randomElement(using: &generator) ?? "")
        }
        return parts.joined(separator: " ")
    }

    private static func tags(language: String, using generator: inout SplitMix64) -> [GalleryTag] {
        var tags = [tag("language", [language])]
        let pools: [(String, [String], ClosedRange<Int>)] = [
            ("parody", parodies.map { $0.lowercased() }, 0...2),
            ("character", characters, 0...4),
            ("artist", artists.map { $0.lowercased() }, 0...2),
            ("female", femaleTags, 0...12),
            ("male", maleTags, 0...6),
            ("other", otherTags, 0...4)
        ]
        for (namespace, pool, range) in pools {
            let count = Int.random(in: range, using: &generator)
            guard count > 0 else { continue }
            tags.append(tag(namespace, Array(pool.shuffled(using: &generator).prefix(count))))
        }
        return tags
    }

    private static func tag(_ namespace: String, _ texts: [String]) -> GalleryTag {
        GalleryTag(rawNamespace: namespace, contents: texts.map {
            GalleryTag.Content(rawNamespace: namespace, text: $0, isVotedUp: false, isVotedDown: false, backgroundColor: nil)
        })
    }

    private static let languages = ["japanese", "japanese", "japanese", "english", "english", "chinese", "korean", "spanish"]
    private static let circles = ["Studio Kimigabuchi", "Alice no Takarabako", "Kaiki Nisshoku", "Nekomataya", "Hapoi-Dokoro"]
    private static let artists = ["Kimimaru", "Mizuryu Kei", "Mizuki Gai", "Nekomata Naomi", "Tsukino Jyogi", "Asanagi"]
    private static let parodies = ["Original", "Touhou Project", "Kantai Collection", "Fate Grand Order", "Blue Archive"]
    private static let characters = ["reimu hakurei", "marisa kirisame", "shimakaze", "mash kyrielight", "hoshino takanashi", "yuuka"]
    private static let uploaders = ["Pokom", "nekomimi", "Hentai Hunter", "Anonymous", "mmmmmmmmmmmmmmmmmmmm", "zwarte"]
    private static let words = [
        "Summer", "Festival", "Secret", "Lesson", "After", "School", "Diary", "Night", "Memories", "Sister", "Love",
        "Story", "Princess", "Holiday", "Rain", "Morning", "Promise", "Garden", "Ribbon", "Sweet", "Days", "Zero",
        "Collection", "Vol. 2", "Chapter 7", "Extra", "Re:", "Kyou no", "Ano Hi", "Mitai na", "Monogatari"
    ]
    private static let femaleTags = [
        "sole female", "glasses", "ponytail", "twintails", "school uniform", "swimsuit", "stockings", "kemonomimi",
        "dark skin", "maid", "kimono", "nurse", "bunny girl", "pantyhose", "elf", "tomboy", "big breasts", "smell"
    ]
    private static let maleTags = ["sole male", "glasses", "dark skin", "shotacon", "muscle", "bald", "tall man"]
    private static let otherTags = ["full color", "story arc", "multi-work series", "uncensored", "mosaic censorship", "webtoon"]
}

/// A small seeded generator, so every run builds the same galleries.
nonisolated struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}
#endif
