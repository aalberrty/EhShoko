import EhCore
import UIKit
#if DEBUG || HARNESS
import Synchronization
#endif

/// Reads a page's patch file and makes its patches ready to draw. All of it runs off the main
/// actor: the file's read, the decoding of its one bitmap, and a copy of each patch in the
/// form the display takes without converting it. What is left for the main actor is to make a
/// layer for each patch.
///
/// Nothing is kept: a page view loads its overlay when it gets its page and drops it when it
/// is reused, so the overlays in memory are those of the pages that have a view.
nonisolated enum ReaderTranslationOverlayLoader {
    /// Throws `PageTranslationOverlayUnreadable` for a file that is missing or damaged, and
    /// `CancellationError`.
    @concurrent
    static func load(_ overlay: PageTranslationOverlay) async throws -> PageTranslationPatches {
        #if DEBUG || HARNESS
        loads.withLock { $0 += 1 }
        #endif
        var patches = try await overlay.patches()
        for index in patches.patches.indices {
            try Task.checkCancellation()
            // The patches of a file are parts of one bitmap. Each gets a bitmap of its own,
            // decoded for the display: Core Animation would otherwise make that copy on the
            // main thread, in the commit that first shows the layer. It also lets the file's
            // bitmap, with the space between its patches, go.
            if let prepared = UIImage(cgImage: patches.patches[index].image).preparingForDisplay()?.cgImage {
                patches.patches[index].image = prepared
            }
        }
        return patches
    }

    #if DEBUG || HARNESS
    /// How many overlays were asked for since launch, for the reader harness: switching
    /// between the original and the translation must not add one.
    static var loadCount: Int { loads.withLock { $0 } }

    private static let loads = Mutex(0)
    #endif
}
