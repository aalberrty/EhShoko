import SwiftUI

/// Shelf's first screen, Home (`shelf.md` section 2): a header of shelves over the Front
/// Page list.
///
/// **Adapter.** Until task B1 builds it, this shows today's Home, so the app has a first
/// screen under every choice. B1 replaces this file and keeps the initializer, which is what
/// `StartScreen` calls. The built screen is `GalleryListScreen(context:header:)` for Front
/// Page with `embedsInStart`, the shelves as its header.
struct ShelfHomeView: View {
    var body: some View {
        HomeScreen()
            // Home keeps its account button under `command`; under `tabs` the shell adds it.
            .startAccountButton()
    }
}
