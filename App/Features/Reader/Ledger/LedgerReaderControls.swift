import EhFeatures
import SwiftUI

/// Ledger's reader controls (`ledger.md` section 5): the two-height control sheet.
///
/// **Adapter.** Until task E3 builds them, this shows today's control panel, so the reader
/// works under every choice. E3 replaces this file and keeps the initializer, which is what
/// `ReaderScreen` calls.
struct LedgerReaderControls: View {
    let model: ReaderModel
    let viewport: ReaderViewport

    var body: some View {
        ReaderControlPanel(model: model)
            .readerDestinationSheets(model)
    }
}
