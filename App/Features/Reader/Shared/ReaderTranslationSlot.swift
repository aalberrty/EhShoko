import EhFeatures
import SwiftUI

/// Where a design keeps a translation control: Shelf's Translate button and state capsule,
/// Wall's leading circle, three-way pill and toast, Ledger's two buttons and its translation
/// group (`shelf.md`, `wall.md`, `ledger.md`, section 5).
///
/// While the model reports `.unavailable` (a gallery in another language) the slot puts
/// nothing in the hierarchy: the content is not even created, and takes no room. This is the
/// one place that decides whether translation shows. In every other case the content shows,
/// and a press of its Translate does what the case says (`ReaderModel.toggleTranslation()`):
///
/// | Availability | The content |
/// |---|---|
/// | `.needsModels` | The control; a press opens the download sheet |
/// | `.installing(progress)` | The control with the download's progress (`downloadFraction`, `installingText`); a press opens the sheet |
/// | `.ready` | The control; a press turns Translate on or off in this reader |
///
/// The pieces every design's content shares are in `Reader/Shared/Translation/`: the status
/// texts, the mark for pages translated before and what VoiceOver reads.
struct ReaderTranslationSlot<Content: View>: View {
    let availability: ReaderTranslationAvailability
    @ViewBuilder let content: () -> Content

    var body: some View {
        switch availability {
        case .unavailable:
            EmptyView()
        case .needsModels, .installing, .ready:
            content()
        }
    }
}
