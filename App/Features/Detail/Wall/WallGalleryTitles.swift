import EhFeatures
import EhModels
import SwiftUI

/// What the card writes about a gallery's two titles (`wall.md` section 4, items 1, 2 and 7):
/// the title is the parsed core of the title the app shows (the Japanese one when the setting
/// asks for it and there is one), the credit is the circle and artists that title names, and
/// the other title is shown in full at the foot of the panel, so nothing the title leaves out
/// is lost.
///
/// Made once per change of the titles, not per render: the panel keeps the last in a cache.
nonisolated struct WallGalleryTitles: Equatable {
    /// What the titles are made from: the list's title until the page has loaded.
    struct Source: Equatable {
        let title: String
        let japaneseTitle: String?
        let prefersJapanese: Bool
    }

    let source: Source
    /// The title the card shows, in full.
    let shown: String
    let parsed: ParsedTitle
    /// The full string of the title the card does not show, or, without one, the shown title's
    /// own full string when parsing shortened it. `nil` when it would repeat the title.
    let other: String?

    init(_ source: Source) {
        self.source = source
        let japanese = source.japaneseTitle.flatMap { $0.isEmpty ? nil : $0 }
        let shown = source.prefersJapanese ? japanese ?? source.title : source.title
        self.shown = shown
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

    /// "Circle · Artist, Artist", as Wall writes a credit; `nil` when the title names neither.
    var credit: String? {
        let names = parsed.artists.joined(separator: ", ")
        switch (parsed.circle, names.isEmpty) {
        case (let circle?, false): return "\(circle) · \(names)"
        case (let circle?, true): return circle
        case (nil, false): return names
        case (nil, true): return nil
        }
    }

    /// Whether the credit names more than one name, so a tap offers a menu.
    var creditHasSeveralNames: Bool {
        (parsed.circle == nil ? 0 : 1) + parsed.artists.count > 1
    }

    /// The circle and artists as searches, matched against the gallery's tags. Asked when the
    /// credit is tapped or its menu opens, so the heading does not follow the tags.
    func creditSearches(in gallery: Gallery, tags: [GalleryTag]) -> [GalleryCreditSearch] {
        var shownGallery = gallery
        shownGallery.title = shown
        if !tags.isEmpty { shownGallery.tags = tags }
        return GalleryCreditSearch.targets(for: GalleryEntry(gallery: shownGallery))
    }
}

/// Keeps the titles made last, so a title is parsed once per change and not once per render.
/// Not observable: filling it draws nothing again.
final class WallGalleryTitleCache {
    private var titles: WallGalleryTitles?

    func titles(for source: WallGalleryTitles.Source) -> WallGalleryTitles {
        if let titles, titles.source == source { return titles }
        let made = WallGalleryTitles(source)
        titles = made
        return made
    }
}
