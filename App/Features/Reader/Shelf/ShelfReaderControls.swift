import EhFeatures
import SwiftUI

/// Shelf's reader controls (`shelf.md` section 5): a top bar and a bottom panel.
///
/// **Adapter.** Until task E1 builds them, this shows today's control panel, so the reader
/// works under every choice. E1 replaces this file and keeps the initializer, which is what
/// `ReaderScreen` calls.
struct ShelfReaderControls: View {
    let model: ReaderModel
    let viewport: ReaderViewport

    var body: some View {
        ReaderControlPanel(model: model)
            .readerDestinationSheets(model)
    }
}
