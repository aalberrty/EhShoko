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
        /// The scroll view has been seen at `offset`.
        var isSettled = false
    }

    /// How far the content is scrolled, 0 at its top under the bars: the value
    /// `ScrollPosition.scrollTo(y:)` takes.
    private(set) var offset: CGFloat = 0
    /// Where the first row of covers starts in the content.
    var cellsTop: CGFloat = 0
    /// The wall has appeared and not disappeared since: not under a pushed screen, nor in a
    /// tab that is not shown.
    var isOnScreen = false
    private var kept: Kept?

    func moved(to offset: CGFloat) {
        self.offset = offset
        if let kept, abs(offset - kept.offset) < 1 {
            self.kept?.isSettled = true
        }
    }

    /// The row an earlier change kept, while the wall is laid out as `map` and still where
    /// that change left it (or on its way there). It is judged when asked for, not when the
    /// offset is reported: iOS 18 reports the offset before the change once more after the
    /// new one, and a row forgotten for that slipped at the next change.
    func kept(in map: WallGridMap) -> Kept? {
        guard let kept, kept.map == map, !kept.isSettled || abs(offset - kept.offset) < 1 else { return nil }
        return kept
    }

    func keep(_ anchor: Int?, at offset: CGFloat, in map: WallGridMap) {
        kept = anchor.map { Kept(anchor: $0, offset: offset, map: map) }
    }

    /// Someone scrolls, or the entries are others: the row at the top is another.
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
/// a first screen passes comes first, across the width, then what stands between it and the
/// covers, the covers, Toplists' later pages each under their divider, and the footer.
///
/// The grid holds the covers, and they are its own items, not a section's content. The
/// header and the top line stand before it and the footer after it, in the stack around it.
/// A lazy grid whose cells are a `Section`'s content builds rows at twice the scroll offset
/// while a finger scrolls it, cells nobody sees that are built once more when their turn
/// comes; and with a heading or a footer among its items it does not place a far row
/// exactly, so a density change that keeps a row in place landed rows from it.
///
/// The grid is a new one whenever its columns or its density change (`WallArrangement`). A
/// lazy grid keeps the heights of the rows it has measured, and kept them through a change
/// of its columns: after a density change it then placed its rows by the old heights, and
/// the row to keep was rows away (17 of them, 90 rows down a wall of three columns). A new
/// grid has measured nothing and places its rows where they are. Its cells on screen are
/// made again, once for each change.
///
/// A numbered list's pages keep the form all lists had (`numbered`): one grid whose
/// sections are the pages, each under its divider, with the header, the top line and the
/// footer as sections of their own. Its cells are built ahead as described, and a density
/// change several pages down lands rows from the row it kept. The dividers have to be among
/// the grid's rows, and no other way to hold them worked: as headers of sections that hold
/// nothing, with the cells as the grid's items, the grid on iOS 18 ends before its last
/// row; a grid for each page keeps the cells of every page that has left the screen.
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
    let pages: RankedPages?
    let primary: ListPrimaryControl?
    let cue: WallDensityCue
    /// The gallery open in the side pane, whose cover is outlined.
    let selectedID: String?
    let prefetcher: ListCoverPrefetcher
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
        ScrollView {
            Group {
                if let pages {
                    numbered(pages)
                } else {
                    plain(entries, phase: phase)
                }
            }
            // Entries that change inside someone else's animation (the find field closing) take
            // their places at once: what a lazy grid lays out must not be animated.
            .transaction(value: ListEntriesKey(entries)) { $0.animation = nil }
            .background { ScrollViewPinch(onStep: step) }
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
        .onChange(of: ListEntriesKey(entries), initial: true) {
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

    /// Where the covers start, for telling which row is at the top.
    private var top: some View {
        WallListTop(input: input, primary: primary)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.frame(in: .named(WallListSpace.name)).maxY
            } action: { [tracker] maxY in
                tracker.cellsTop = maxY
            }
    }

    /// Every list but a numbered one with its pages: the covers alone in the grid.
    private func plain(_ entries: [GalleryEntry], phase: ListFeed.Phase) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // A child of the scroll view's content itself, so a first screen's scroll to its
            // top finds it, and at full width: a header brings its own margins.
            header
            VStack(alignment: .leading, spacing: 0) {
                top
                LazyVGrid(columns: columns, alignment: .leading, spacing: 0) {
                    switch phase {
                    case .loading:
                        placeholders(layout.columns * Self.placeholderRows(layout.density))
                    case .content:
                        cells(entries[...])
                        if input.feed.footer == .loading {
                            placeholders(Self.nextPageTiles(after: entries.count, columns: layout.columns))
                        }
                    case .signedOut, .empty, .failed:
                        EmptyView()
                    }
                }
                .id(WallArrangement(layout))
                // In a lazy stack of its own: the footer asks for the next page when it
                // appears, which in the plain stack around it would be at once. The stack is
                // as high as the footer is at least, so that it is reached: on iOS 18 a lazy
                // stack that has built nothing has no height, and one at the very end of the
                // content never came on screen.
                LazyVStack(spacing: 0) {
                    footer(phase)
                }
                .frame(minHeight: Self.footerMinimum(phase), alignment: .top)
            }
            .padding(.horizontal, WallGridLayout.margin)
        }
        .coordinateSpace(.named(WallListSpace.name))
    }

    /// A numbered list's pages, in the form all lists had: sections of one grid.
    private func numbered(_ pages: RankedPages) -> some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 0) {
            // A direct item of the grid, so a first screen's scroll to its top finds it, and
            // at full width: a header brings its own margins.
            Section {} header: {
                header.padding(.horizontal, -WallGridLayout.margin)
            }
            Section {
                rankedCells(pages.first)
            } header: {
                top
            }
            ForEach(pages.later) { page in
                Section {
                    rankedCells(page.rows)
                } header: {
                    WallListPageDivider(page: page.number, height: style.texts.metrics.dividerHeight)
                }
            }
            if input.feed.footer == .loading {
                Section { placeholders(layout.columns) }
            }
            Section {} footer: {
                footer(.content)
            }
        }
        .coordinateSpace(.named(WallListSpace.name))
        .padding(.horizontal, WallGridLayout.margin)
    }

    /// About a screenful on a phone while the first page loads.
    private static func placeholderRows(_ density: WallDensity) -> Int {
        switch density {
        case .large: 3
        case .medium: 4
        case .small: 7
        }
    }

    /// The tiles that stand for a page on its way: what the last row lacks, and a row more.
    private static func nextPageTiles(after count: Int, columns: Int) -> Int {
        (columns - count % columns) % columns + columns
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

    private func rankedCells(_ rows: ArraySlice<RankedEntry>) -> some View {
        ForEach(rows) { row in
            WallCoverCell(entry: row.entry, rank: row.rank, isSelected: row.id == selectedID, style: style).equatable()
                .contentShape(.rect)
                .onTapGesture { openGallery(row.entry.gallery) }
                .accessibilityAddTraits(.isButton)
                .galleryContextMenu(row.entry, actions: input.actions)
                .onAppear { prefetcher.appeared(row.id) }
        }
    }

    /// The least the footer of a phase is high.
    private static func footerMinimum(_ phase: ListFeed.Phase) -> CGFloat {
        switch phase {
        case .content: WallListFooter.minimumHeight
        case .signedOut, .empty, .failed: stateHeight
        case .loading: 0
        }
    }

    @ViewBuilder
    private func footer(_ phase: ListFeed.Phase) -> some View {
        switch phase {
        case .content:
            WallListFooter(footer: input.feed.footer, retry: input.feed.retryNextPage)
                .loadsNextPage(of: input.feed)
        case .signedOut, .empty, .failed:
            // Under a header: the state below it. In the scroll view, so its buttons are
            // filled, not glass.
            WallListState(input: input)
                .statusActionForm(.filled)
                .frame(maxWidth: .infinity, minHeight: Self.stateHeight)
        case .loading:
            EmptyView()
        }
    }

    /// A state under a header takes at least this much of the wall.
    private static var stateHeight: CGFloat { 360 }
}

/// What a grid's rows depend on: which cells share a row, and the form they have.
private struct WallArrangement: Hashable {
    let density: WallDensity
    let columns: Int

    init(_ layout: WallGridLayout) {
        density = layout.density
        columns = layout.columns
    }
}

/// The content's coordinate space, in which the top of the covers is measured.
nonisolated private enum WallListSpace {
    static let name = "WallListGrid"
}
