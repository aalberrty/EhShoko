#if DEBUG
import EhCore
import EhModels
import SwiftUI

/// The list views the harness can measure. A list design adds a case here and a branch in
/// `ListHarnessSlotView`, giving its view the harness's galleries (and the entries mapped from
/// them, once lists take entries); nothing else in the harness changes. The raw value is the
/// name `-HarnessSlot` and `measure.sh` use.
nonisolated enum ListHarnessSlot: String, CaseIterable, Identifiable, Sendable {
    /// v3's list rows (`GalleryDetailRow` in a `List`), the "Detail" display mode.
    case v3Rows = "v3-rows"
    /// v3's grid of cards (`GalleryThumbnailCell` in a `LazyVGrid`), the "Thumbnail" display mode.
    case v3Grid = "v3-grid"
    /// v3's list rows with the cover drawn by `CoverImage` (one decode per cover, at the site's
    /// size) instead of `RemoteImage` (one decode per display size).
    case v3RowsCover = "v3-rows-cover"

    var id: String { rawValue }
}

/// The view under test for a slot. The harness scrolls whichever scroll view this contains.
struct ListHarnessSlotView: View {
    let slot: ListHarnessSlot
    let galleries: [Gallery]
    /// v3's cells read the display mode and the tag settings from the environment, so the
    /// harness gives them a store of its own rather than the user's.
    let settings: SettingsStore

    var body: some View {
        switch slot {
        case .v3Rows, .v3Grid:
            GalleryCollection(galleries: galleries)
                .environment(settings)
        case .v3RowsCover:
            ListHarnessCoverRows(galleries: galleries)
                .environment(settings)
        }
    }
}
#endif
