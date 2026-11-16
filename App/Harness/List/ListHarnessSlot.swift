#if DEBUG || HARNESS
import Dependencies
import EhCore
import EhModels
import SwiftUI

/// The list views the harness can measure. A list design adds a case here and a branch in
/// `ListHarnessSlotView`, giving its view the harness's galleries (as one loaded list,
/// `ListHarnessFeed`); nothing else in the harness changes. The raw value is the name
/// `-HarnessSlot` and `measure.sh` use.
nonisolated enum ListHarnessSlot: String, CaseIterable, Identifiable, Sendable {
    /// v3's list rows (`GalleryDetailRow` in a `List`), the "Detail" display mode.
    case v3Rows = "v3-rows"
    /// v3's grid of cards (`GalleryThumbnailCell` in a `LazyVGrid`), the "Thumbnail" display mode.
    case v3Grid = "v3-grid"
    /// v3's list rows with the cover drawn by `CoverImage` (one decode per cover, at the site's
    /// size) instead of `RemoteImage` (one decode per display size).
    case v3RowsCover = "v3-rows-cover"
    /// Shelf's list as Front Page (`-HarnessTags YES` for its tag line), and as Toplists, with
    /// ranks.
    case shelf
    case shelfRanked = "shelf-ranked"
    /// Wall's list as Front Page at each density.
    case wallLarge = "wall-large"
    case wallMedium = "wall-medium"
    case wallSmall = "wall-small"
    /// Ledger's list as Front Page, with day headings: with covers, and titles only.
    case ledger
    case ledgerTitles = "ledger-titles"

    var id: String { rawValue }

    /// The density a Wall slot measures; `nil` for the other slots.
    var wallDensity: WallDensity? {
        switch self {
        case .wallLarge: .large
        case .wallMedium: .medium
        case .wallSmall: .small
        default: nil
        }
    }
}

/// The view under test for a slot. The harness scrolls whichever scroll view this contains.
struct ListHarnessSlotView: View {
    let slot: ListHarnessSlot
    let galleries: [Gallery]
    /// v3's cells read the display mode and the tag settings from the environment, and the list
    /// designs their own form settings, so the harness gives them a store of its own rather
    /// than the user's.
    let settings: SettingsStore

    @Dependency(\.userStore) private var userStore
    @Dependency(\.filterStore) private var filterStore

    var body: some View {
        content
            .environment(settings)
            .environment(userStore)
            .environment(filterStore)
    }

    @ViewBuilder
    private var content: some View {
        switch slot {
        case .v3Rows, .v3Grid:
            GalleryCollection(galleries: galleries)
        case .v3RowsCover:
            ListHarnessCoverRows(galleries: galleries)
        case .shelf, .shelfRanked:
            ShelfListHarnessSlot(feed: ListHarnessFeed.feed(for: galleries), isRanked: slot == .shelfRanked)
        case .wallLarge, .wallMedium, .wallSmall:
            WallListHarnessSlot(feed: ListHarnessFeed.feed(for: galleries))
        case .ledger, .ledgerTitles:
            LedgerListHarnessSlot(feed: ListHarnessFeed.feed(for: galleries))
        }
    }
}
#endif
