import Kingfisher
import UIKit

/// The covers being loaded, one load per URL however many views ask for it.
///
/// Kingfisher joins two requests for one URL while it downloads, not while it reads the
/// original from the disk cache: two `CoverImage`s asking for a cover in the same frame each
/// read and decoded it (a list under its Continue shelf, the tab accessory over a list, two
/// piles of Wall's library). Here the second asks the first's load for its result, so a cover
/// is decoded once wherever it is shown.
///
/// A load is cancelled when every view that asked for it has gone away, and forgotten when it
/// ends, so nothing is held between loads: the bitmaps are the memory cache's.
@MainActor
final class CoverLoads {
    enum Outcome {
        case image(UIImage)
        case failed
        case cancelled
    }

    static let shared = CoverLoads()

    /// `CoverProcessor`, the original to the disk cache and the bitmap to memory only: what
    /// `CoverImage` asks for and what the lists' prefetchers fetch.
    static let options: KingfisherOptionsInfo = [
        .processor(CoverProcessor.shared), .cacheOriginalImage, .cacheMemoryOnly,
    ]

    private static let parsedOptions = KingfisherParsedOptionsInfo(options)

    private final class Load {
        var task: Task<UIImage?, Never>?
        /// The callers waiting for it, and how many of them were cancelled since.
        var waiters = 0
        var cancelled = 0
    }

    private var loads: [URL: Load] = [:]

    private init() {}

    /// The decoded cover when it is in the memory cache: a lookup, nothing is read or decoded.
    static func memoryImage(for url: URL?) -> UIImage? {
        guard let url else { return nil }
        return ImageCache.default.retrieveImageInMemoryCache(forKey: url.cacheKey, options: parsedOptions)
    }

    /// The cover at `url`, from the load already running for it or from a new one.
    func load(_ url: URL) async -> Outcome {
        let load = loads[url] ?? start(url)
        load.waiters += 1
        let image = await withTaskCancellationHandler {
            await load.task?.value
        } onCancel: {
            Task { @MainActor in self.waiterCancelled(url, load) }
        }
        if Task.isCancelled { return .cancelled }
        return image.map(Outcome.image) ?? .failed
    }

    private func start(_ url: URL) -> Load {
        let load = Load()
        loads[url] = load
        load.task = Task {
            let image = try? await KingfisherManager.shared.retrieveImage(with: url, options: Self.options).image
            if loads[url] === load { loads[url] = nil }
            return image
        }
        return load
    }

    /// Stops the load once nobody waits for it any more. A waiter that was cancelled keeps
    /// waiting while others do; it ignores the result.
    private func waiterCancelled(_ url: URL, _ load: Load) {
        guard loads[url] === load else { return }
        load.cancelled += 1
        guard load.cancelled >= load.waiters else { return }
        loads[url] = nil
        load.task?.cancel()
    }
}
