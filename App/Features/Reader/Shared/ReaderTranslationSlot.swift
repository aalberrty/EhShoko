import EhFeatures
import SwiftUI

/// Where a design keeps a translation control: Shelf's Translate button and state capsule,
/// Wall's leading circle, three-way pill and toast, Ledger's two buttons and its translation
/// group (`shelf.md`, `wall.md`, `ledger.md`, section 5).
///
/// While the model reports `.unavailable` (a gallery in another language) the slot puts
/// nothing in the hierarchy: the content is not even created, and takes no room. This is the
/// one place that decides what shows. The other cases show nothing yet either: the designs'
/// controls come with their own tasks.
struct ReaderTranslationSlot<Content: View>: View {
    let availability: ReaderTranslationAvailability
    @ViewBuilder let content: () -> Content

    var body: some View {
        switch availability {
        case .unavailable, .needsModels, .installing, .ready:
            EmptyView()
        }
    }
}
