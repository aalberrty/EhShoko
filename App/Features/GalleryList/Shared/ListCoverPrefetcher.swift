import EhFeatures
import Kingfisher
import SwiftUI

/// Fetches the covers ahead of the scroll, for every list design (`Design/designs/README.md`
/// section 9.3, `spikes/S1.md`): when a row within `lead` of the last cover asked for appears,
/// the next `batch` covers are asked for, with `CoverImage`'s options so they land decoded where
/// its cells look, and the batch before, if it is still running, is stopped. One batch at a
/// time, so the fan-out is bounded to `batch` URLs and Kingfisher's own downloads at once.
/// Without it every cover arrives after its cell, which then renders twice (S1: about 15% more
/// main-thread time a row).
///
/// At Wall's Small density a screenful is more covers than a batch and a fast scroll passes
/// them quicker than five downloads at once deliver: a larger batch would not change that.
///
/// A list view owns one as `@State` (a plain class: nothing observes it), gives it the rows
/// whenever they may have changed (`update(_:)` is cheap when they have not), reports rows from
/// their `onAppear` and stops it when the list goes away.
final class ListCoverPrefetcher {
    static let batch = 24
    static let lead = 12

    /// Whether the rows show covers: Ledger's titles-only rows have none, and nothing is fetched.
    var isEnabled = true

    private var urls: [URL?] = []
    private var indexByID: [String: Int] = [:]
    /// The first and last rows given, which tell more rows of the same list from another list.
    private var firstID: String?
    private var lastID: String?
    /// Covers before this index have been asked for.
    private var watermark = 0
    private var current: ImagePrefetcher?

    private static let options = CoverImage.prefetchOptions + [.alsoPrefetchToMemory]

    /// Takes the list's rows. Rows appended to the same list keep the progress made and only
    /// they are indexed; another list (or the rows narrowed by Find) starts over.
    func update(_ entries: [GalleryEntry]) {
        let first = entries.first?.id
        guard first != firstID || entries.last?.id != lastID || entries.count != urls.count else { return }
        let isSameList = first == firstID
        let grew = isSameList && !urls.isEmpty && entries.count > urls.count && entries[urls.count - 1].id == lastID
        if !isSameList {
            stop()
            watermark = 0
        }
        if !grew {
            urls.removeAll(keepingCapacity: true)
            indexByID.removeAll(keepingCapacity: true)
        }
        urls.reserveCapacity(entries.count)
        for index in urls.count..<entries.count {
            let entry = entries[index]
            if indexByID[entry.id] == nil {
                indexByID[entry.id] = index
            }
            urls.append(entry.gallery.coverURL)
        }
        watermark = min(watermark, urls.count)
        firstID = first
        lastID = entries.last?.id
    }

    /// Called from a row's `onAppear`.
    func appeared(_ id: String) {
        guard isEnabled, let index = indexByID[id], index + Self.lead >= watermark, watermark < urls.count else { return }
        // After a jump the covers in between are their cells' own business.
        let start = max(watermark, index + 1)
        let end = min(start + Self.batch, urls.count)
        guard start < end else { return }
        watermark = end
        let batch = urls[start..<end].compactMap(\.self)
        guard !batch.isEmpty else { return }
        // What the last batch has not fetched yet is on screen by now, where its cells load it.
        current?.stop()
        let prefetcher = ImagePrefetcher(urls: batch, options: Self.options)
        current = prefetcher
        prefetcher.start()
    }

    /// The list went away.
    func stop() {
        current?.stop()
        current = nil
    }
}

/// What tells a list that its rows changed: another first row (another list, or the rows
/// narrowed by Find), or more rows.
struct ListEntriesKey: Equatable {
    let first: String?
    let count: Int

    init(_ entries: [GalleryEntry]) {
        first = entries.first?.id
        count = entries.count
    }
}
