import EhModels
import Foundation

/// Which drawing of a page's text a patch file holds: the models that made the text, the
/// repaint choice and the version of the drawing rules. Changing the repaint choice or the
/// rules draws pages again into a new folder and keeps their text.
public struct PageTranslationPatchVariant: Sendable, Hashable {
    public var modelSet: PageTranslationModelSet
    public var repaint: RepaintChoice
    /// The drawing rules' version, raised whenever they would draw a page differently.
    public var renderVersion: Int

    public init(modelSet: PageTranslationModelSet, repaint: RepaintChoice, renderVersion: Int) {
        self.modelSet = modelSet
        self.repaint = repaint
        self.renderVersion = renderVersion
    }

    /// Such as `k2xl768.cpt2.jmt1.t1.lamamanga.r1`: letters, digits and dots only.
    public var folderName: String {
        "\(modelSet.key).\(repaint.key).r\(renderVersion)"
    }
}

/// Where patch files are kept: `Library/Caches/PageTranslation/<gid>/<variant>/<page>.patch`.
///
/// Patch files can always be drawn again from the stored text, so they live in Caches, where
/// the system may delete them, and are held to `limit`: past it, whole galleries are removed,
/// the one used longest ago first, until 80% is left. A gallery's folder carries the date it
/// was last used as its modification date.
///
/// The store keeps the folder's size in memory once it has measured it, so a write costs one
/// `stat` and no scan. Nothing here runs at launch: the store measures and expires on first use.
/// The process has one store, `\.pageTranslationPatchStore`.
public actor PageTranslationPatchStore {
    /// 300 MB: one to three thousand pages at 100 to 400 KB each.
    public static let defaultLimit = 300 * 1024 * 1024
    /// How much of the limit eviction leaves.
    public static let keptFraction = 0.8

    public static var defaultDirectory: URL {
        URL.cachesDirectory.appending(path: "PageTranslation", directoryHint: .isDirectory)
    }

    public nonisolated let directory: URL
    public nonisolated let limit: Int
    private let fileManager = FileManager()
    /// The folder's size in bytes as last measured, plus what was written since; `nil` until the
    /// first measurement.
    private var knownSize: Int?

    public init(directory: URL = PageTranslationPatchStore.defaultDirectory, limit: Int = defaultLimit) {
        self.directory = directory
        self.limit = limit
    }

    /// Where the patch file of one page is. Only builds the path.
    public nonisolated func fileURL(gid: String, pageIndex: Int, variant: PageTranslationPatchVariant) -> URL {
        galleryFolder(gid)
            .appending(path: variant.folderName, directoryHint: .isDirectory)
            .appending(path: "\(pageIndex).patch", directoryHint: .notDirectory)
    }

    /// Makes the folder for a page's patch file, marks its gallery as used and returns where the
    /// file goes. The caller writes the file and then calls `didWrite(_:)`.
    public func prepareToWrite(gid: String, pageIndex: Int, variant: PageTranslationPatchVariant) throws -> URL {
        let url = fileURL(gid: gid, pageIndex: pageIndex, variant: variant)
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        markUsed(gid: gid)
        return url
    }

    /// Counts a file just written at `url`, and removes galleries when the folder is now over the
    /// limit. A file written again in place is counted twice until the next measurement, which
    /// at most starts an eviction a little early; eviction measures everything again first.
    public func didWrite(_ url: URL) {
        let total: Int
        if let knownSize {
            let size = (try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey]))?.totalFileAllocatedSize ?? 0
            total = knownSize + size
        } else {
            // The first measurement already includes the new file.
            total = measure()
        }
        knownSize = total
        if total > limit {
            evict()
        }
    }

    /// Marks a gallery as used now, so eviction removes it after galleries used before it. The
    /// service calls it when a reader with Translate on shows the gallery's stored pages.
    public func markUsed(gid: String, at date: Date = .now) {
        setLastUsed(date, of: galleryFolder(gid))
    }

    /// The size of every patch file on disk, in bytes, measured now: what Settings shows for
    /// translated pages. The text in the database is not counted: 1 to 4 KB a page, a few MB
    /// for thousands of pages, and measuring it would read every row.
    public func size() -> Int {
        let total = measure()
        knownSize = total
        return total
    }

    /// Removes galleries, the one used longest ago first, until at most `keptFraction` of the
    /// limit is left. The gallery used last is never removed, so a gallery larger than the
    /// limit keeps its pages while it is read.
    public func evictIfNeeded() {
        if (knownSize ?? measure()) > limit {
            evict()
        }
    }

    /// Removes the patch files of every variant but `variant`, and every gallery not used within
    /// `interval` before `now`, then evicts if the folder is still over the limit. The service
    /// calls it the first time it is used in a process, beside the database's expiry; never at
    /// launch.
    public func removeExpired(
        keeping variant: PageTranslationPatchVariant,
        notUsedWithin interval: TimeInterval = PageTranslationResultWriter.retention,
        now: Date = .now
    ) {
        let cutoff = now.addingTimeInterval(-interval)
        for gallery in galleries() {
            if gallery.lastUsed < cutoff {
                try? fileManager.removeItem(at: gallery.url)
                continue
            }
            let variants = (try? fileManager.contentsOfDirectory(at: gallery.url, includingPropertiesForKeys: nil)) ?? []
            let stale = variants.filter { $0.lastPathComponent != variant.folderName }
            guard !stale.isEmpty else { continue }
            stale.forEach { try? fileManager.removeItem(at: $0) }
            // Removing a folder inside it changed the gallery's date, which says when it was used.
            setLastUsed(gallery.lastUsed, of: gallery.url)
        }
        knownSize = measure()
        evictIfNeeded()
    }

    /// Removes one gallery's patch files.
    public func removeGallery(gid: String) {
        try? fileManager.removeItem(at: galleryFolder(gid))
        knownSize = nil
    }

    /// Removes every patch file (Settings' Clear).
    public func removeAll() {
        try? fileManager.removeItem(at: directory)
        knownSize = 0
    }

    // MARK: - Measuring and evicting

    private struct GalleryFolder {
        let url: URL
        let lastUsed: Date
        let size: Int
    }

    private func evict() {
        let target = Int(Double(limit) * Self.keptFraction)
        let folders = galleries().sorted { $0.lastUsed < $1.lastUsed }
        var total = folders.reduce(0) { $0 + $1.size }
        for folder in folders.dropLast() where total > target {
            try? fileManager.removeItem(at: folder.url)
            total -= folder.size
        }
        knownSize = total
    }

    private func setLastUsed(_ date: Date, of folder: URL) {
        try? fileManager.setAttributes([.modificationDate: date], ofItemAtPath: folder.path)
    }

    private func measure() -> Int {
        galleries().reduce(0) { $0 + $1.size }
    }

    private func galleries() -> [GalleryFolder] {
        let urls = (try? fileManager.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey]
        )) ?? []
        return urls.compactMap { url in
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isDirectoryKey])
            guard values?.isDirectory == true else { return nil }
            return GalleryFolder(url: url, lastUsed: values?.contentModificationDate ?? .distantPast, size: size(of: url))
        }
    }

    private func size(of folder: URL) -> Int {
        let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .isRegularFileKey]
        guard let files = fileManager.enumerator(at: folder, includingPropertiesForKeys: Array(keys)) else { return 0 }
        var total = 0
        for case let file as URL in files {
            guard let values = try? file.resourceValues(forKeys: keys), values.isRegularFile == true else { continue }
            total += values.totalFileAllocatedSize ?? 0
        }
        return total
    }

    /// A gallery's folder. A gid is digits; anything else is percent-encoded, so no gid can name
    /// a folder outside the store.
    private nonisolated func galleryFolder(_ gid: String) -> URL {
        let name = gid.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "_"
        return directory.appending(path: name.isEmpty ? "_" : name, directoryHint: .isDirectory)
    }
}
