import Kingfisher
import SwiftUI

/// Fetches and decodes the covers ahead of the scroll (`README.md` section 9.3, spike S1):
/// when a row within `lead` of the last cover asked for appears, the next `batch` covers go to
/// one `ImagePrefetcher` with `CoverImage`'s options, so a prefetched cover is the entry the
/// row's `CoverImage` finds, and the batch before, if it still runs, is stopped. One batch at
/// a time bounds the fan-out to `batch` URLs. Without it every cover arrives after its row
/// and the row draws twice (S1: about 15% more main-thread time a row).
///
/// Held as `@State` of `LedgerListView`, a plain class that nothing observes; the list stops
/// it when it goes away. Titles-only rows have no covers, so it does nothing for them. Wall's
/// and Shelf's lists need the same object; it could move to a shared place.
final class LedgerCoverPrefetcher {
    static let batch = 24
    static let lead = 12

    /// Whether the rows show covers.
    var isEnabled = true
    /// Covers before this index have been asked for.
    private var watermark = 0
    private var current: ImagePrefetcher?

    private static let options = CoverImage.prefetchOptions + [.alsoPrefetchToMemory]

    /// Called from the row at `index` of `urls` when it appears.
    func rowAppeared(at index: Int, of urls: [URL?]) {
        guard isEnabled, index + Self.lead >= watermark else { return }
        if watermark > urls.count {
            // The list was replaced by a shorter one: start again from where the rows are.
            watermark = 0
        }
        // After a jump the covers in between are the rows' own business.
        let start = max(watermark, index + 1)
        let end = min(start + Self.batch, urls.count)
        guard start < end else { return }
        watermark = end
        let batch = urls[start..<end].compactMap(\.self)
        // What it has not fetched yet is on screen by now, where the rows load it.
        current?.stop()
        let prefetcher = ImagePrefetcher(urls: batch, options: Self.options)
        current = prefetcher
        prefetcher.start()
    }

    /// The list went away, or was replaced.
    func stop() {
        current?.stop()
        current = nil
        watermark = 0
    }
}
