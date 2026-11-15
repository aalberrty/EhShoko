import EhFeatures
import EhModels

/// What the closing page writes about the gallery's title, worked out off the main actor:
/// the parsed title, the credit under it and the "More by" search (`closing-page.md`, items 3
/// and 6). They come from the list's title, so they are there at once, and from the detail's
/// preferred title once it is known.
nonisolated struct ReaderClosingTitles: Equatable, Sendable {
    /// The title these were worked out from.
    let source: String
    /// The title as the reader shows it: the parsed core, or the whole title when it does not
    /// follow the site's convention.
    let title: String
    /// "Circle · Artist", or `nil` when the title names neither.
    let credit: String?
    /// The circle, else the first artist, as the tag search the list's menu offers.
    let moreBy: Search?

    struct Search: Equatable, Sendable {
        let name: String
        let keyword: String
    }

    /// Before the title has been parsed: the title as it is.
    static func unparsed(_ title: String) -> ReaderClosingTitles {
        ReaderClosingTitles(source: title, title: title, credit: nil, moreBy: nil)
    }

    @concurrent
    static func make(title: String, gallery: Gallery) async -> ReaderClosingTitles {
        var titled = gallery
        titled.title = title
        let entry = GalleryEntry(gallery: titled)
        let search = GalleryCreditSearch.targets(for: entry).first
        return ReaderClosingTitles(
            source: title,
            title: entry.title.core,
            credit: entry.credit,
            moreBy: search.map { Search(name: $0.name, keyword: $0.keyword) }
        )
    }
}
