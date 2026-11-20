import EhModels

/// The circle and the artists a gallery's parsed title names, each as a search: what the
/// lists' menus and swipe actions, the gallery pages and the reader's closing page offer as
/// "Search <name>".
nonisolated public struct GalleryCreditSearch: Identifiable, Equatable, Sendable {
    /// Whom the search is for. The app gives each its symbol.
    public enum Kind: Sendable {
        case circle, artist
    }

    public let name: String
    public let keyword: String
    public let kind: Kind

    public var id: String { keyword }

    public init(name: String, keyword: String, kind: Kind) {
        self.name = name
        self.keyword = keyword
        self.kind = kind
    }

    /// At most the circle and three artists. A name that matches one of the gallery's tags in
    /// the same namespace searches that tag exactly; otherwise the name in quotes.
    public static func targets(for entry: GalleryEntry) -> [GalleryCreditSearch] {
        let title = entry.title
        let tags = entry.gallery.tags
        var targets: [GalleryCreditSearch] = []
        if let circle = title.circle, !circle.isEmpty {
            targets.append(target(circle, namespace: .group, kind: .circle, tags: tags))
        }
        for artist in title.artists.prefix(3) where !artist.isEmpty {
            targets.append(target(artist, namespace: .artist, kind: .artist, tags: tags))
        }
        // A circle named after its one artist would otherwise appear twice.
        var seen = Set<String>()
        return targets.filter { seen.insert($0.keyword).inserted }
    }

    private static func target(_ name: String, namespace: TagNamespace, kind: Kind, tags: [GalleryTag]) -> Self {
        let lowered = name.lowercased()
        let match = tags.first { $0.namespace == namespace }.flatMap { tag in
            tag.contents.first { $0.text.lowercased() == lowered }.map { $0.searchKeyword(tag: tag) }
        }
        return GalleryCreditSearch(name: name, keyword: match ?? "\"\(name)\"", kind: kind)
    }
}
