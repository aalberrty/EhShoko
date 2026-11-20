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
    /// Shelf's list as Front Page (`-HarnessTags YES` for its tag line), and as Toplists, with
    /// ranks.
    case shelf
    case shelfRanked = "shelf-ranked"
    /// Shelf's Home: the same list under Home's header (title, Continue, Popular now).
    case shelfHome = "shelf-home"
    /// Shelf's list in its lazy grid whatever the width: at a phone's width one column of the
    /// same rows, where the app uses its `List`.
    case shelfGrid = "shelf-grid"
    /// Wall's list as Front Page at each density, and at the middle one as Toplists, with
    /// ranks.
    case wallLarge = "wall-large"
    case wallMedium = "wall-medium"
    case wallSmall = "wall-small"
    case wallRanked = "wall-ranked"
    /// Ledger's list as Front Page, with day headings: with covers, and titles only.
    case ledger
    case ledgerTitles = "ledger-titles"

    var id: String { rawValue }

    /// The design the slot's list belongs to, whose look it is drawn in unless `-HarnessLook`
    /// asks for another.
    var design: DesignStyle {
        switch self {
        case .shelf, .shelfRanked, .shelfHome, .shelfGrid: .shelf
        case .wallLarge, .wallMedium, .wallSmall, .wallRanked: .wall
        case .ledger, .ledgerTitles: .ledger
        }
    }

    /// The density a Wall slot measures; `nil` for the other slots.
    var wallDensity: WallDensity? {
        switch self {
        case .wallLarge: .large
        case .wallMedium, .wallRanked: .medium
        case .wallSmall: .small
        default: nil
        }
    }
}

/// The view under test for a slot. The harness scrolls whichever scroll view this contains.
struct ListHarnessSlotView: View {
    let slot: ListHarnessSlot
    let galleries: [Gallery]
    /// The galleries in each page of a ranked slot's list; 0 for one page.
    var pageSize = 0
    /// The list designs read their own form settings from the environment, so the harness gives
    /// them a store of its own rather than the user's.
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
        case .shelf, .shelfRanked:
            ShelfListHarnessSlot(
                feed: ListHarnessFeed.feed(for: galleries, pageSize: slot == .shelfRanked ? pageSize : 0),
                isRanked: slot == .shelfRanked
            )
        case .shelfGrid:
            ShelfListHarnessSlot(feed: ListHarnessFeed.feed(for: galleries), isRanked: false)
                .environment(\.shelfListAlwaysUsesGrid, true)
        case .shelfHome:
            ListHarnessShelfHome(feed: ListHarnessFeed.feed(for: galleries))
        case .wallLarge, .wallMedium, .wallSmall:
            WallListHarnessSlot(feed: ListHarnessFeed.feed(for: galleries), isRanked: false)
        case .wallRanked:
            WallListHarnessSlot(feed: ListHarnessFeed.feed(for: galleries, pageSize: pageSize), isRanked: true)
        case .ledger, .ledgerTitles:
            LedgerListHarnessSlot(feed: ListHarnessFeed.feed(for: galleries))
        }
    }
}
extension EnvironmentValues {
    /// The list harness's `shelf-grid` slot: Shelf's list draws its lazy grid at any width.
    @Entry var shelfListAlwaysUsesGrid = false
}
#endif
