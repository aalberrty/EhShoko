import EhFeatures
import EhModels
import Foundation

/// One pile of Wall's library: All or a folder, its name and count, and its three cards. Made
/// once per change of the page, so a pile formats nothing.
nonisolated struct WallPile: Identifiable, Equatable, Sendable {
    /// One of the three places of a pile.
    enum Card: Equatable, Sendable {
        /// One of the newest covers the app has for the folder.
        case cover(URL)
        /// A cover not drawn yet: the page is on its way, or the cover is being decoded for
        /// two piles at once (`WallPileCovers.shared(in:)`). Drawn as a cover's placeholder.
        case pending
        /// The page is here and holds no more of the folder's galleries: a tile in the
        /// folder's colour (All's is neutral).
        case tile
    }

    /// 0 to 9, or `WallPile.allFolders`.
    let folder: Int
    let name: String
    /// Formatted; `nil` while the count is unknown.
    let count: String?
    /// `coversPerPile` cards: the front one, then the one behind it on the left and the one
    /// on the right.
    let cards: [Card]

    var id: Int { folder }

    static let allFolders = -1
    static let coversPerPile = 3
    /// The site has ten folders, 0 to 9.
    static let folderCount = 10
}

/// Which covers each pile shows: from the favourites the app has loaded, never a request of
/// their own (`wall.md` section 7).
nonisolated enum WallPileCovers {
    /// The first three covers of all the entries, and the first three of each folder: from
    /// the folder's own galleries when it was opened this session (`folders`, 0 to 9), else
    /// from the entries' folder marks. Both are in the order the site listed them, which is
    /// newest first in either of its orders. Entries with no cover are skipped; one with no
    /// folder mark counts for All only.
    ///
    /// Stops as soon as every pile filled from `entries` has its three, so it reads a page of
    /// 25 to 200 entries at most once.
    static func covers(in entries: [GalleryEntry], folders: [Int: [GalleryEntry]] = [:]) -> [Int: [URL]] {
        var covers: [Int: [URL]] = [:]
        for (folder, galleries) in folders {
            covers[folder] = Array(galleries.lazy.compactMap(\.gallery.coverURL).prefix(WallPile.coversPerPile))
        }
        var openPiles = WallPile.folderCount + 1 - folders.count
        for entry in entries {
            guard openPiles > 0 else { break }
            guard let url = entry.gallery.coverURL else { continue }
            if add(url, to: WallPile.allFolders, in: &covers) { openPiles -= 1 }
            if let folder = entry.favorite?.folder, folders[folder] == nil, add(url, to: folder, in: &covers) {
                openPiles -= 1
            }
        }
        return covers
    }

    /// The covers shown in two piles at once: All's newest are also their folders' newest.
    ///
    /// Two cover views asking for one cover in the same frame each decode it when it comes
    /// from the disk cache, which does not join the two loads as the downloader does. So the
    /// page decodes these once itself, and both piles draw them once that is done.
    static func shared(in covers: [Int: [URL]]) -> Set<URL> {
        let all = Set(covers[WallPile.allFolders] ?? [])
        guard !all.isEmpty else { return [] }
        var shared = Set<URL>()
        for (folder, urls) in covers where folder != WallPile.allFolders {
            shared.formUnion(urls.filter(all.contains))
        }
        return shared
    }

    /// A pile's three cards: its covers, as many as it has, then tiles once the page is
    /// here, or placeholders while it is on its way. A cover in `held` is a placeholder too.
    static func cards(_ covers: [URL], held: Set<URL>, isLoaded: Bool) -> [WallPile.Card] {
        (0..<WallPile.coversPerPile).map { place in
            guard place < covers.count else { return isLoaded ? .tile : .pending }
            let url = covers[place]
            return held.contains(url) ? .pending : .cover(url)
        }
    }

    /// Adds `url` to `pile` unless it is full; returns whether that filled it.
    private static func add(_ url: URL, to pile: Int, in covers: inout [Int: [URL]]) -> Bool {
        var pileCovers = covers[pile, default: []]
        guard pileCovers.count < WallPile.coversPerPile else { return false }
        pileCovers.append(url)
        covers[pile] = pileCovers
        return pileCovers.count == WallPile.coversPerPile
    }
}
