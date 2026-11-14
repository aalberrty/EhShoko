import EhFeatures
import SwiftUI

/// Wall's reader controls (`wall.md` section 5): the scrub capsule and the rising filmstrip.
///
/// **Adapter.** Until task E2 builds them, this shows today's control panel, so the reader
/// works under every choice. E2 replaces this file and keeps the initializer, which is what
/// `ReaderScreen` calls.
struct WallReaderControls: View {
    let model: ReaderModel
    let viewport: ReaderViewport

    var body: some View {
        ReaderControlPanel(model: model)
            .readerDestinationSheets(model)
    }
}
