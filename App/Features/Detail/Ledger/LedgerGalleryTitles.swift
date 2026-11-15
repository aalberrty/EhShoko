import EhFeatures
import EhModels
import Foundation

/// What the header writes about a gallery's titles (`ledger.md` section 4, header), from the
/// model's parsed titles (`GalleryDetailModel.titles`), so the page's first frame shows the
/// title parsed.
///
/// The title shown large is the parsed core of the preferred title; the line above it names
/// the event and the release notes the title carries; the credit (`ParsedTitle.credit`) is its
/// circle and artists; the other title is the other language's full string, or the preferred
/// title in full when there is no other and parsing shortened it.
nonisolated struct LedgerGalleryTitles: Equatable, Sendable {
    let shown: ShownGalleryTitle
    /// "C103 · Digital": the event and the flags, in title order.
    let notes: [String]
    /// What a tap on the credit searches: the circle and up to three artists. Empty until they
    /// have been matched against the tags (`creditSearches(for:gallery:)`).
    let creditSearches: [GalleryCreditSearch]

    init(_ shown: ShownGalleryTitle, creditSearches: [GalleryCreditSearch] = []) {
        self.shown = shown
        var notes = shown.parsed.event.map { [$0] } ?? []
        notes.append(contentsOf: shown.parsed.flags)
        self.notes = notes
        self.creditSearches = creditSearches
    }

    var parsed: ParsedTitle { shown.parsed }
    var otherTitle: String? { shown.other }

    /// The credit's searches for the title `shown`, matched against `gallery`'s tags, away
    /// from the main actor.
    @concurrent
    static func creditSearches(for shown: String, gallery: Gallery) async -> [GalleryCreditSearch] {
        // The searches name what the header shows, which may be the Japanese title rather than
        // the list's.
        var titled = gallery
        titled.title = shown
        return GalleryCreditSearch.targets(for: GalleryEntry(gallery: titled))
    }
}

/// The credit's searches, with the title they were made for.
nonisolated struct LedgerCreditSearches: Equatable, Sendable {
    let title: String
    let searches: [GalleryCreditSearch]
}
