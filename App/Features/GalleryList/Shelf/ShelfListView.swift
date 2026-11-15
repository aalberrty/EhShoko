import SwiftUI

/// Shelf's list of galleries (`shelf.md` section 3).
///
/// **Adapter.** Until task C1 builds it, this shows today's list, so every list works
/// under every choice. C1 replaces this file and keeps the initializer, which is what
/// `GalleryListScreen` calls. `input` is everything the list is given
/// (`ListDesignInput`); `header` goes first in the design's lazy container.
struct ShelfListView<Header: View>: View {
    let input: ListDesignInput
    @ViewBuilder var header: Header

    var body: some View {
        V3ListBody(input: input, header: header)
    }
}
