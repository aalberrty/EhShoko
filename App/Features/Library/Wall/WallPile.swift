import EhFeatures
import Foundation

/// One pile of Wall's library: All or a folder, its name and count, and the newest covers the
/// app already has for it. Made once per change of the page, so a pile formats nothing.
nonisolated struct WallPile: Identifiable, Equatable, Sendable {
    /// What the pile's empty places are drawn as.
    enum Tiles: Equatable, Sendable {
        /// The page is still on its way: neutral tiles.
        case waiting
        /// The page is here and holds fewer than three of the folder's galleries: tiles in
        /// the folder's colour (All's are neutral).
        case folder
    }

    /// 0 to 9, or `WallPile.allFolders`.
    let folder: Int
    let name: String
    /// Formatted; `nil` while the count is unknown.
    let count: String?
    /// At most `coversPerPile`, the newest first.
    let covers: [URL]
    let tiles: Tiles

    var id: Int { folder }

    static let allFolders = -1
    static let coversPerPile = 3
    /// The site has ten folders, 0 to 9.
    static let folderCount = 10
}

/// Which covers each pile shows: from the favourites the app has loaded, never a request of
/// their own (`wall.md` section 7).
nonisolated enum WallPileCovers {
    /// The first three covers of all the entries, and the first three of each folder, in the
    /// order the site listed them, which is newest first in either of its orders. Entries
    /// with no cover are skipped; one with no folder mark counts for All only.
    ///
    /// Stops as soon as every pile has its three, so it reads a page of 25 to 200 entries
    /// at most once.
    static func covers(in entries: [GalleryEntry]) -> [Int: [URL]] {
        var covers: [Int: [URL]] = [:]
        var fullPiles = 0
        let pileCount = WallPile.folderCount + 1
        for entry in entries {
            guard let url = entry.gallery.coverURL else { continue }
            if add(url, to: WallPile.allFolders, in: &covers) { fullPiles += 1 }
            if let folder = entry.favorite?.folder, add(url, to: folder, in: &covers) { fullPiles += 1 }
            if fullPiles == pileCount { break }
        }
        return covers
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
