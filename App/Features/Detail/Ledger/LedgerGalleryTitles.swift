import EhFeatures
import EhModels
import Foundation

/// What the header writes about a gallery's titles, worked out off the main actor from the
/// titles the page has (`ledger.md` section 4, header).
///
/// The title shown large is the parsed core of the preferred title; the line above it names
/// the event and the release notes the title carries; the credit (`ParsedTitle.credit`) is its
/// circle and artists; the other title is the other language's full string, or the preferred
/// title in full when there is no other and parsing shortened it.
nonisolated struct LedgerGalleryTitles: Equatable, Sendable {
    /// The titles it is made from: the preferred one first.
    struct Source: Hashable, Sendable {
        let preferred: String
        let other: String?
    }

    let source: Source
    let parsed: ParsedTitle
    /// "C103 · Digital": the event and the flags, in title order.
    let notes: [String]
    /// What a tap on the credit searches: the circle and up to three artists.
    let creditSearches: [GalleryCreditSearch]
    let otherTitle: String?

    /// Before the title has been parsed: the title as it is, with nothing taken out of it.
    static func unparsed(_ source: Source) -> LedgerGalleryTitles {
        LedgerGalleryTitles(
            source: source, parsed: ParsedTitle(raw: source.preferred), notes: [], creditSearches: [],
            otherTitle: source.other
        )
    }

    /// Parses `source` away from the main actor. `gallery` gives the tags a credit search
    /// matches its names against.
    @concurrent
    static func make(_ source: Source, gallery: Gallery) async -> LedgerGalleryTitles {
        let parsed = TitleParser.parse(source.preferred)
        let entry = GalleryEntry(gallery: gallery, title: parsed, languageCode: nil)
        var notes = parsed.event.map { [$0] } ?? []
        notes.append(contentsOf: parsed.flags)
        let shortened = parsed.isParsed && parsed.core != source.preferred
        return LedgerGalleryTitles(
            source: source, parsed: parsed, notes: notes,
            creditSearches: GalleryCreditSearch.targets(for: entry),
            otherTitle: source.other ?? (shortened ? source.preferred : nil)
        )
    }

    /// The titles of `model`'s gallery in the order `prefersJapanese` asks for. Before the page
    /// has loaded, the list's title alone.
    @MainActor
    static func source(of model: GalleryDetailModel, prefersJapanese: Bool) -> Source {
        guard let detail = model.detail else {
            return Source(preferred: model.gallery.title, other: nil)
        }
        let japanese = detail.jpnTitle.flatMap { $0.isEmpty ? nil : $0 }
        if prefersJapanese, let japanese {
            return Source(preferred: japanese, other: detail.title)
        }
        return Source(preferred: detail.title, other: japanese)
    }
}
