import EhModels

/// One row of a gallery list, as every list design draws it: the gallery and what a row shows
/// that is derived from it, computed once when its page is mapped, off the main actor.
public nonisolated struct GalleryEntry: Identifiable, Equatable, Sendable {
    public let gallery: Gallery
    public let title: ParsedTitle
    /// "EN", "ZH", …: from the gallery's language tag, else from its title; `nil` when neither
    /// names one.
    public let languageCode: String?
    /// Which favourites folder holds it, from the page it came with.
    public let favorite: FavoriteMark?
    /// The page last read, when known.
    public let readingProgress: Int?

    public var id: String { gallery.gid }

    /// Parses the title. Call it off the main actor.
    public init(gallery: Gallery, favorite: FavoriteMark? = nil, readingProgress: Int? = nil) {
        let title = TitleParser.parse(gallery.title)
        self.init(
            gallery: gallery, title: title, languageCode: Self.languageCode(of: gallery, title: title),
            favorite: favorite, readingProgress: readingProgress
        )
    }

    public init(
        gallery: Gallery, title: ParsedTitle, languageCode: String?,
        favorite: FavoriteMark? = nil, readingProgress: Int? = nil
    ) {
        self.gallery = gallery
        self.title = title
        self.languageCode = languageCode
        self.favorite = favorite
        self.readingProgress = readingProgress
    }

    /// `title` and `languageCode` follow from `gallery`, so they are not compared.
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.gallery == rhs.gallery && lhs.favorite == rhs.favorite && lhs.readingProgress == rhs.readingProgress
    }

    static func languageCode(of gallery: Gallery, title: ParsedTitle) -> String? {
        if let code = gallery.language?.code { return code }
        return title.language.flatMap(TitleParser.language(named:))?.code
    }
}

extension GalleryEntry {
    /// Entries for `galleries`, with their favourite marks. An entry in `previous` for the same
    /// version of a gallery is reused, so a gallery's title is parsed once however often its
    /// list is re-read.
    nonisolated static func entries(
        for galleries: [Gallery], marks: [String: FavoriteMark] = [:], reusing previous: [GalleryEntry] = []
    ) -> [GalleryEntry] {
        let known = previous.isEmpty
            ? [:] : Dictionary(previous.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return galleries.map { gallery in
            let favorite = marks[gallery.gid]
            if let entry = known[gallery.gid], entry.gallery == gallery {
                return entry.favorite == favorite ? entry : entry.with(favorite: favorite)
            }
            return GalleryEntry(gallery: gallery, favorite: favorite)
        }
    }

    nonisolated func with(favorite: FavoriteMark?) -> GalleryEntry {
        GalleryEntry(
            gallery: gallery, title: title, languageCode: languageCode,
            favorite: favorite, readingProgress: readingProgress
        )
    }
}
