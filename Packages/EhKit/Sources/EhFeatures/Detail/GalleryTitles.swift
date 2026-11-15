import EhModels

/// A gallery page's two titles, each parsed once, so that no design parses a title while it
/// draws. `GalleryDetailModel.titles` holds them: the list's title from the start, then the
/// titles of the page, parsed off the main actor before the page is shown.
public nonisolated struct GalleryTitles: Equatable, Sendable {
    /// The title the site lists first (romanised or English).
    public let title: String
    public let parsedTitle: ParsedTitle
    /// The title in its original script; `nil` when the page has none (or before it is there).
    public let japaneseTitle: String?
    public let parsedJapaneseTitle: ParsedTitle?

    /// Parses both titles. An empty Japanese title counts as none.
    public init(title: String, japaneseTitle: String? = nil) {
        let japanese = japaneseTitle.flatMap { $0.isEmpty ? nil : $0 }
        self.title = title
        parsedTitle = TitleParser.parse(title)
        self.japaneseTitle = japanese
        parsedJapaneseTitle = japanese.map(TitleParser.parse)
    }

    /// The titles of `detail`, parsed away from the caller's actor.
    @concurrent
    static func make(for detail: GalleryDetail) async -> GalleryTitles {
        GalleryTitles(title: detail.title, japaneseTitle: detail.jpnTitle)
    }

    /// What a page shows: the Japanese title when `prefersJapanese` and there is one,
    /// otherwise the title. Picks among parsed values; nothing is parsed here.
    public func shown(prefersJapanese: Bool) -> ShownGalleryTitle {
        if prefersJapanese, let japaneseTitle, let parsedJapaneseTitle {
            return ShownGalleryTitle(full: japaneseTitle, parsed: parsedJapaneseTitle, counterpart: title)
        }
        return ShownGalleryTitle(full: title, parsed: parsedTitle, counterpart: japaneseTitle)
    }

    /// The parsed values follow from the strings.
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.title == rhs.title && lhs.japaneseTitle == rhs.japaneseTitle
    }
}

/// The title a page shows, parsed, and the one it does not.
public nonisolated struct ShownGalleryTitle: Equatable, Sendable {
    /// The shown title in full.
    public let full: String
    public let parsed: ParsedTitle
    /// What a page writes beneath the parsed title so that nothing is lost: the other title in
    /// full, or, without one, the shown title in full when parsing shortened it. `nil` when it
    /// would repeat what is shown.
    public let other: String?

    init(full: String, parsed: ParsedTitle, counterpart: String?) {
        self.full = full
        self.parsed = parsed
        if let counterpart, counterpart != full {
            other = counterpart
        } else if parsed.core != full {
            other = full
        } else {
            other = nil
        }
    }
}
