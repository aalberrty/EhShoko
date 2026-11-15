import EhFeatures
import EhModels
import SwiftUI

/// Where the wall is scrolled to, kept outside SwiftUI's state: the offset changes on every
/// frame of a scroll and nothing must be invalidated by it. A plain class held as `@State`.
final class WallListTracker {
    /// The row a density change kept in place, for the next change to keep again.
    struct Kept {
        let anchor: Int
        /// The offset that change asked for.
        let offset: CGFloat
        /// The layout it was made in: a later change in another one starts afresh.
        let map: WallGridMap
        /// The scroll view has been seen at `offset`, so leaving it means someone scrolled.
        var isSettled = false
    }

    /// How far the content is scrolled, 0 at its top under the bars: the value
    /// `ScrollPosition.scrollTo(y:)` takes.
    private(set) var offset: CGFloat = 0
    /// Where the first row of covers starts in the content.
    var cellsTop: CGFloat = 0
    private(set) var kept: Kept?

    func moved(to offset: CGFloat) {
        self.offset = offset
        guard let kept else { return }
        if abs(offset - kept.offset) < 1 {
            self.kept?.isSettled = true
        } else if kept.isSettled {
            // Scrolled since, by a finger or by the system: the row at the top is another.
            self.kept = nil
        }
    }

    func keep(_ anchor: Int?, at offset: CGFloat, in map: WallGridMap) {
        kept = anchor.map { Kept(anchor: $0, offset: offset, map: map) }
    }

    func forget() {
        kept = nil
    }
}

/// The wall as a whole for a moment after a density change made at once: a little larger or
/// smaller, as the covers were, and faded. One transform on one layer, in place of an
/// animation of every cell, which a lazy grid cannot do (`spikes/S1.md`).
struct WallDensityCue: Equatable {
    var scale: CGFloat = 1
    var opacity: Double = 1

    static let rest = WallDensityCue()

    /// - Parameter moves: false under Reduce Motion, where the change is a cross-fade.
    init(from old: WallGridLayout, to new: WallGridLayout, moves: Bool) {
        scale = moves ? min(max(old.pitch / new.pitch, 0.94), 1.06) : 1
        opacity = 0.55
    }

    private init() {}
}

/// The wall (`wall.md` section 3): a lazy grid of `WallCoverCell` in a scroll view. The header
/// a first screen passes is its first item across the columns, then what stands between it and
/// the covers, the covers, Toplists' later pages each under their divider, and the footer.
///
/// Inside each `ForEach` the cell and its modifiers are written out without a condition
/// (`spikes/S1.md`, rule 1). The grid adds no spacing of its own: the space under a row is
/// part of the cell, and every other item has a given height or none, so that where a row is
/// follows from the layout alone (`WallGridMap`).
struct WallListGrid<Header: View>: View {
    let input: ListDesignInput
    let header: Header
    let style: WallCellStyle
    let layout: WallGridLayout
    let pages: WallListPages?
    let primary: ListPrimaryControl?
    let cue: WallDensityCue
    /// The gallery open in the side pane, whose cover is outlined.
    let selectedID: String?
    let prefetcher: WallListPrefetcher
    let tracker: WallListTracker
    @Binding var position: ScrollPosition
    /// A pinch: `+1` for larger covers, `-1` for smaller.
    let step: (Int) -> Void

    @Environment(\.openGallery) private var openGallery
    @Environment(\.look) private var look

    var body: some View {
        let feed = input.feed
        let entries = feed.entries
        let phase = feed.phase
        let isLoadingMore = phase == .content && feed.footer == .loading
        ScrollView {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 0) {
                // A direct item of the grid, so a first screen's scroll to its top finds it,
                // and at full width: a header brings its own margins.
                Section {} header: {
                    header.padding(.horizontal, -WallGridLayout.margin)
                }
                Section {
                    switch phase {
                    case .loading:
                        placeholders(layout.columns * Self.placeholderRows(layout.density))
                    case .content:
                        if let pages {
                            rankedCells(pages.first)
                        } else {
                            cells(entries[...])
                            if isLoadingMore { placeholders(layout.columns) }
                        }
                    case .signedOut, .empty, .failed:
                        EmptyView()
                    }
                } header: {
                    // Where the covers start, for telling which row is at the top.
                    WallListTop(input: input, primary: primary)
                        .onGeometryChange(for: CGFloat.self) { proxy in
                            proxy.frame(in: .named(WallListSpace.name)).maxY
                        } action: { [tracker] maxY in
                            tracker.cellsTop = maxY
                        }
                }
                if let pages {
                    ForEach(pages.later) { page in
                        Section {
                            rankedCells(page.rows)
                        } header: {
                            WallListPageDivider(page: page.number, height: style.texts.metrics.dividerHeight)
                        }
                    }
                    if isLoadingMore {
                        Section { placeholders(layout.columns) }
                    }
                }
                Section {} footer: {
                    footer(phase)
                }
            }
            .coordinateSpace(.named(WallListSpace.name))
            // Entries that change inside someone else's animation (the find field closing) take
            // their places at once: what a lazy grid lays out must not be animated.
            .transaction(value: WallListEntriesKey(entries)) { $0.animation = nil }
            .padding(.horizontal, WallGridLayout.margin)
            .background { WallListPinch(onStep: step) }
        }
        .scrollPosition($position)
        // Only the scale and the fade move, and only here: no animation may reach what the
        // lazy grid lays out.
        .animation(.snappy(duration: 0.25)) { $0.scaleEffect(cue.scale).opacity(cue.opacity) }
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top
        } action: { [tracker] _, offset in
            tracker.moved(to: offset)
        }
        .onScrollPhaseChange { [tracker] _, phase in
            if phase == .interacting || phase == .decelerating { tracker.forget() }
        }
        .background(look.background)
        .refreshable { await feed.refresh() }
        .onChange(of: WallListEntriesKey(entries), initial: true) {
            prefetcher.update(entries)
            tracker.forget()
        }
    }

    private var columns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(), spacing: layout.columnSpacing, alignment: .top),
            count: layout.columns
        )
    }

    /// About a screenful on a phone while the first page loads.
    private static func placeholderRows(_ density: WallDensity) -> Int {
        switch density {
        case .large: 3
        case .medium: 4
        case .small: 7
        }
    }

    private func placeholders(_ count: Int) -> some View {
        ForEach(0..<count, id: \.self) { _ in
            WallPlaceholderCell(style: style)
        }
    }

    private func cells(_ entries: ArraySlice<GalleryEntry>) -> some View {
        let offersMove = input.context.signInKind == .favorites
        return ForEach(entries) { entry in
            WallCoverCell(entry: entry, isSelected: entry.id == selectedID, style: style).equatable()
                .contentShape(.rect)
                // A tap gesture, not a `Button`: a pinch must not open the covers under the
                // fingers, and a finger that moves fails a tap gesture.
                .onTapGesture { openGallery(entry.gallery) }
                .accessibilityAddTraits(.isButton)
                .galleryContextMenu(entry, actions: input.actions, offersMove: offersMove)
                .onAppear { prefetcher.appeared(entry.id) }
        }
    }

    private func rankedCells(_ rows: ArraySlice<WallRankedEntry>) -> some View {
        ForEach(rows) { row in
            WallCoverCell(entry: row.entry, rank: row.rank, isSelected: row.id == selectedID, style: style).equatable()
                .contentShape(.rect)
                .onTapGesture { openGallery(row.entry.gallery) }
                .accessibilityAddTraits(.isButton)
                .galleryContextMenu(row.entry, actions: input.actions)
                .onAppear { prefetcher.appeared(row.id) }
        }
    }

    @ViewBuilder
    private func footer(_ phase: ListFeed.Phase) -> some View {
        switch phase {
        case .content:
            WallListFooter(footer: input.feed.footer, retry: input.feed.retryNextPage)
                .loadsNextPage(of: input.feed)
        case .signedOut, .empty, .failed:
            // Under a header: the state below it.
            WallListState(input: input)
                .frame(maxWidth: .infinity, minHeight: Self.stateHeight)
        case .loading:
            EmptyView()
        }
    }

    /// A state under a header takes at least this much of the wall.
    private static var stateHeight: CGFloat { 360 }
}

/// The grid's coordinate space, in which the top of the covers is measured.
nonisolated private enum WallListSpace {
    static let name = "WallListGrid"
}

/// A Toplists cover with its rank.
struct WallRankedEntry: Identifiable {
    let entry: GalleryEntry
    /// 1-based; `nil` while Find narrows the list, when a cover's rank is not known.
    let rank: Int?

    var id: String { entry.id }
}

/// Toplists' covers by the page they came from: the first page's, then each later page with
/// its number for the "Page 2" divider. Ranks count from the page's number, so a list opened
/// at page 5 starts at 201.
struct WallListPages {
    struct Page: Identifiable {
        let number: Int
        let rows: ArraySlice<WallRankedEntry>

        var id: Int { number }
    }

    let first: ArraySlice<WallRankedEntry>
    let later: [Page]

    /// Toplists' pages, when fewer than two are loaded to measure one by.
    private static let pageSize = 50

    /// How many covers each section of the grid holds, in order.
    var sections: [Int] {
        [first.count] + later.map(\.rows.count)
    }

    init(entries: [GalleryEntry], pageStarts: [PageStart], findText: String) {
        guard let start = pageStarts.first else {
            // Popular (one page), or Find narrowing the list: no pages to tell apart.
            let ranks = findText.isEmpty
            first = entries.enumerated().map { WallRankedEntry(entry: $1, rank: ranks ? $0 + 1 : nil) }[...]
            later = []
            return
        }
        let pageSize = pageStarts.count > 1 ? pageStarts[1].index - start.index : Self.pageSize
        var rows: [WallRankedEntry] = []
        rows.reserveCapacity(entries.count)
        // Where each page's covers are in `rows`.
        var bounds: [(number: Int, range: Range<Int>)] = []
        for (offset, page) in pageStarts.enumerated() {
            let end = offset + 1 < pageStarts.count ? pageStarts[offset + 1].index : entries.count
            let lower = min(page.index, entries.count)
            let base = (page.page - 1) * pageSize + 1
            let rowsStart = rows.count
            for index in lower..<max(min(end, entries.count), lower) {
                rows.append(WallRankedEntry(entry: entries[index], rank: base + index - lower))
            }
            bounds.append((page.page, rowsStart..<rows.count))
        }
        first = rows[bounds.first?.range ?? 0..<0]
        later = bounds.dropFirst().map { Page(number: $0.number, rows: rows[$0.range]) }
    }
}
