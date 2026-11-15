import EhCore
import EhFeatures
import EhModels
import SwiftUI

/// The signed-in library: "1,284 galleries in 10 folders" under the bar's title, then the
/// eleven piles, three across on a phone and five on a wider screen
/// (`wall.md` section 7, `mockups/wall/06-library-light`).
///
/// It draws the first page of All favourites that `list` holds. Before the page is here the
/// piles are placeholders, already named, since the names are stored; a first page that
/// failed is the shared error view in place of the piles.
struct WallLibraryPage: View {
    /// All favourites, the shared model's; `nil` until the library has chosen it.
    let list: GalleryListModel?
    /// The total under the bar's title. Off under `tabs`, where the screen has no title.
    let showsSummary: Bool
    /// A folder's list; `WallPile.allFolders` is every folder.
    let open: (Int) -> Void

    @Environment(UserStore.self) private var userStore
    @Environment(\.dynamicTypeSize) private var typeSize
    /// The grid's width, which sets the number of columns and the piles' size.
    @State private var width: CGFloat = 0

    var body: some View {
        let phase = WallLibraryPhase(list)
        // One branch for the placeholders and the piles, so the page arriving keeps the
        // scroll view and fills the same piles.
        if case .failed(let error) = phase {
            ListFailedState(error: error) { list?.retry() }
        } else {
            piles(phase)
        }
    }

    private func piles(_ phase: WallLibraryPhase) -> some View {
        let covers: [Int: [URL]]
        let tiles: WallPile.Tiles
        let stale: AppError?
        switch phase {
        case .loaded(let error):
            covers = WallPileCovers.covers(in: list?.entries ?? [])
            tiles = .folder
            stale = error
        case .waiting, .failed:
            covers = [:]
            tiles = .waiting
            stale = nil
        }
        let columns = columnCount
        let metrics = WallPileMetrics(columnWidth: columnWidth(columns))
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if showsSummary {
                    WallLibrarySummary()
                        .padding(.horizontal, 20)
                        .padding(.bottom, 4)
                }
                if let stale, stale.isNetworkError {
                    ListOfflineBanner(form: .card) { list?.retry() }
                        .padding(.horizontal, Self.margin)
                        .padding(.vertical, 8)
                }
                LazyVGrid(columns: Self.columns(columns), spacing: 16) {
                    ForEach(pileValues(covers, tiles: tiles)) { pile in
                        Button {
                            open(pile.folder)
                        } label: {
                            WallPileView(pile: pile, metrics: metrics).equatable()
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, Self.margin)
                .padding(.top, 4)
            }
            .padding(.bottom, 24)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .refreshable { await list?.refresh() }
    }

    /// All, then the ten folders in the site's order. Names are the site's, stored from the
    /// last favourites page; counts are absent until a page has been loaded this session.
    private func pileValues(_ covers: [Int: [URL]], tiles: WallPile.Tiles) -> [WallPile] {
        let counts = userStore.favoriteFolderCounts
        let all = WallPile(
            folder: WallPile.allFolders, name: L10n.Localizable.Library.all,
            count: userStore.favoriteTotalCount?.formatted(), covers: covers[WallPile.allFolders] ?? [], tiles: tiles
        )
        return [all] + (0..<WallPile.folderCount).map { folder in
            WallPile(
                folder: folder, name: userStore.favoriteFolderName(folder), count: counts[folder]?.formatted(),
                covers: covers[folder] ?? [], tiles: tiles
            )
        }
    }

    // MARK: Columns

    /// Three across on a phone, five where there is room (an iPad, a phone on its side); one
    /// fewer pair at accessibility text sizes, so the names keep some of their width.
    private var columnCount: Int {
        let isWide = width >= Self.wideWidth
        switch (isWide, typeSize.isAccessibilitySize) {
        case (false, false): return 3
        case (false, true): return 2
        case (true, false): return 5
        case (true, true): return 3
        }
    }

    private func columnWidth(_ columns: Int) -> CGFloat {
        guard width > 0 else { return 0 }
        let gaps = Self.columnSpacing * CGFloat(columns - 1)
        return (width - 2 * Self.margin - gaps) / CGFloat(columns)
    }

    private static func columns(_ count: Int) -> [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: columnSpacing, alignment: .top), count: count)
    }

    private static let margin: CGFloat = 12
    private static let columnSpacing: CGFloat = 4
    /// Five piles of the drawn size and their gaps.
    private static let wideWidth: CGFloat = 600
}

/// What the page shows for the list's state.
private enum WallLibraryPhase: Equatable {
    /// No page yet: placeholder piles.
    case waiting
    /// The page is here: piles with its covers. `stale` is a reload's failure while the
    /// earlier page is still shown. A page with no favourites at all comes back as "not
    /// found" and is shown as piles with nothing in them, not as an error.
    case loaded(stale: AppError?)
    /// The first page failed: the shared error view.
    case failed(AppError)

    init(_ list: GalleryListModel?) {
        guard let list else {
            self = .waiting
            return
        }
        let error = list.loadingState.failed
        if !list.entries.isEmpty {
            self = .loaded(stale: error)
        } else if error == .notFound {
            self = .loaded(stale: nil)
        } else if let error {
            self = .failed(error)
        } else {
            self = .waiting
        }
    }
}

/// "1,284 galleries in 10 folders", 14 pt secondary, under the bar's large title. A line of
/// its own height while the counts are unknown, so the piles do not move when they come.
private struct WallLibrarySummary: View {
    @Environment(UserStore.self) private var userStore
    @Environment(\.look) private var look

    var body: some View {
        let counts = userStore.favoriteFolderCounts
        let summary = userStore.favoriteTotalCount.map { L10n.Localizable.Library.summary($0.formatted(), counts.count) }
        Text(summary ?? " ")
            .font(.subheadline)
            .monospacedDigit()
            .foregroundStyle(look.secondaryLabel)
            .lineLimit(2)
            .accessibilityHidden(summary == nil)
    }
}
