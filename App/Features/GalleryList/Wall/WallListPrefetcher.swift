import EhFeatures
import Kingfisher
import SwiftUI

/// Fetches the covers ahead of the scroll (`Design/designs/README.md` section 9.3,
/// `spikes/S1.md`): when a cell within `lead` of the last cover asked for appears, the next
/// `batch` covers are asked for, with `CoverImage`'s options so they land decoded where the
/// cells look, and the batch before, if it is still running, is stopped. One batch at a time,
/// so the fan-out is bounded to `batch` URLs and Kingfisher's own downloads at once. Without
/// it every cover arrives after its cell, which then renders twice.
///
/// At Small a screenful is more covers than a batch and a fast scroll passes them quicker
/// than five downloads at once deliver: a larger batch would not change that.
///
/// `WallListView` owns one as `@State` (a plain class: nothing observes it), feeds it the
/// entries when they change and stops it when the list goes away.
final class WallListPrefetcher {
    static let batch = 24
    static let lead = 12

    private var urls: [URL?] = []
    private var indexByID: [String: Int] = [:]
    /// Covers before this index have been asked for.
    private var watermark = 0
    private var current: ImagePrefetcher?
    /// The first entry's id, which tells a new list from more entries of the same one.
    private var firstID: String?

    /// Takes the list's entries. Appended entries keep the progress made; another list starts
    /// over.
    func update(_ entries: [GalleryEntry]) {
        if entries.first?.id != firstID {
            stop()
            watermark = 0
            firstID = entries.first?.id
        }
        urls = entries.map(\.gallery.coverURL)
        indexByID = Dictionary(entries.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// Called from a cell's `onAppear`.
    func appeared(_ id: String) {
        guard let index = indexByID[id], index + Self.lead >= watermark, watermark < urls.count else { return }
        // After a jump the covers in between are their cells' own business.
        let start = max(watermark, index + 1)
        let end = min(start + Self.batch, urls.count)
        watermark = end
        let batch = start < end ? urls[start..<end].compactMap { $0 } : []
        guard !batch.isEmpty else { return }
        // What the last batch has not fetched yet is on screen by now, where its cells load it.
        current?.stop()
        let prefetcher = ImagePrefetcher(urls: batch, options: CoverImage.prefetchOptions + [.alsoPrefetchToMemory])
        current = prefetcher
        prefetcher.start()
    }

    func stop() {
        current?.stop()
        current = nil
    }
}

/// What tells the prefetcher, and the kept scroll anchor, that the entries changed: another
/// first entry (another list, or the entries narrowed by Find), or more of them.
struct WallListEntriesKey: Equatable {
    let first: String?
    let count: Int

    init(_ entries: [GalleryEntry]) {
        first = entries.first?.id
        count = entries.count
    }
}
