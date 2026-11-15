import EhFeatures
import EhModels
import SwiftUI

/// What Shelf's header shows of a gallery's two titles (`shelf.md` section 4): the heading is
/// the parsed core of the title the app shows (the Japanese one when the setting asks for it
/// and there is one), with the event and the credit that title names; the other title is
/// shown in full beneath, so nothing the heading leaves out is lost.
///
/// Made once per change of the titles, not per render: the header keeps it in its state.
nonisolated struct ShelfGalleryTitles: Equatable {
    /// What the titles are made from: the list's title until the page has loaded.
    struct Source: Equatable {
        let title: String
        let japaneseTitle: String?
        let prefersJapanese: Bool
    }

    let parsed: ParsedTitle
    /// The full string of the title the heading does not show, or, without one, the heading's
    /// own full string when parsing shortened it. `nil` when it would repeat the heading.
    let other: String?

    init(_ source: Source) {
        let japanese = source.japaneseTitle.flatMap { $0.isEmpty ? nil : $0 }
        let shown = source.prefersJapanese ? japanese ?? source.title : source.title
        parsed = TitleParser.parse(shown)
        let counterpart = shown == source.title ? japanese : source.title
        if let counterpart, counterpart != shown {
            other = counterpart
        } else if parsed.core != shown {
            other = shown
        } else {
            other = nil
        }
    }

    var heading: String { parsed.core }

    /// "Circle · Artist, Artist", as Shelf writes a credit; `nil` when the title names neither.
    var credit: String? {
        let names = parsed.artists.joined(separator: ", ")
        switch (parsed.circle, names.isEmpty) {
        case (let circle?, false): return "\(circle) · \(names)"
        case (let circle?, true): return circle
        case (nil, false): return names
        case (nil, true): return nil
        }
    }

    /// The circle and artists as searches, matched against the gallery's tags. Asked when the
    /// credit is tapped or its menu opens, so the header does not follow the tags.
    func creditSearches(in gallery: Gallery, tags: [GalleryTag]) -> [GalleryCreditSearch] {
        var tagged = gallery
        if !tags.isEmpty { tagged.tags = tags }
        return GalleryCreditSearch.targets(for: GalleryEntry(gallery: tagged, title: parsed, languageCode: nil))
    }

    /// Whether the credit names more than one name, so a tap offers a menu.
    var creditHasSeveralNames: Bool {
        (parsed.circle == nil ? 0 : 1) + parsed.artists.count > 1
    }
}
