import EhFeatures
import SwiftUI

/// Wall's search surface (`wall.md` section 6).
///
/// **Adapter.** Until task G2 builds it, this shows today's search screen, which searches
/// everywhere and does not use the shared model. G2 replaces this file and keeps the
/// initializer, which is what `SearchSurface` calls.
struct WallSearchView: View {
    let model: SearchSurfaceModel

    var body: some View {
        SearchScreen()
    }
}
