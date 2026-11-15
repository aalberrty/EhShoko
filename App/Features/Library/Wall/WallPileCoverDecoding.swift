import Kingfisher
import SwiftUI

extension WallPileCovers {
    /// Decodes `urls` once each into the memory cache, with `CoverImage`'s own options, so
    /// the cover views that ask for them afterwards find them decoded and decode nothing.
    /// Used for the covers two piles show at once, at most three; a cover that fails is left
    /// to the cover views, which show their failure.
    @MainActor
    static func decode(_ urls: Set<URL>) async {
        let options = CoverImage.prefetchOptions
        await withTaskGroup(of: Void.self) { group in
            for url in urls {
                group.addTask {
                    _ = try? await KingfisherManager.shared.retrieveImage(with: url, options: options)
                }
            }
        }
    }
}
