import EhFeatures
import SwiftUI

/// Shelf's search surface (`shelf.md` section 6).
///
/// **Adapter.** Until task G1 builds it, this shows today's search screen, which searches
/// everywhere and does not use the shared model. G1 replaces this file and keeps the
/// initializer, which is what `SearchSurface` calls.
struct ShelfSearchView: View {
    let model: SearchSurfaceModel

    var body: some View {
        SearchScreen()
    }
}
