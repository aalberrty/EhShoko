import EhFeatures
import SwiftUI

/// Ledger's search surface (`ledger.md` section 6).
///
/// **Adapter.** Until task G3 builds it, this shows today's search screen, which searches
/// everywhere and does not use the shared model. G3 replaces this file and keeps the
/// initializer, which is what `SearchSurface` calls.
struct LedgerSearchView: View {
    let model: SearchSurfaceModel

    var body: some View {
        SearchScreen()
    }
}
