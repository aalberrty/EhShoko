import EhFeatures
import SwiftUI

/// Where a design keeps a translation control: Shelf's Translate button and state capsule,
/// Wall's leading circle, three-way pill and toast, Ledger's two buttons and its translation
/// group (`shelf.md`, `wall.md`, `ledger.md`, section 5).
///
/// Translation is not built, so the model reports `.unavailable` and the slot puts nothing in
/// the hierarchy: the content is not even created, and takes no room. When translation is
/// built, its availability gains cases and this is the one place that decides what shows.
struct ReaderTranslationSlot<Content: View>: View {
    let availability: ReaderTranslationAvailability
    @ViewBuilder let content: () -> Content

    var body: some View {
        switch availability {
        case .unavailable:
            EmptyView()
        }
    }
}
