import EhFeatures
import EhModels
import SwiftUI

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
/// A numbered list's pages each have a grid of their own, under the page's divider, in the
/// stack (`numbered`, `WallListPage`). The dividers cannot be among one grid's items without
/// the faults above, and as headers of sections that hold nothing the grid on iOS 18 ends
/// before its last row. One grid whose sections were the pages, as it was before, also lost
/// its place about every second time the list came back from under a gallery. A grid that
/// has left the screen keeps every cell it built, so only the pages near the screen are
/// grids, and the others blank space of their height: every height is given, and where a
/// page stands is arithmetic (`ListPageSpans`).
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

    /// What a numbered list drew when a scroll last changed it: which pages, and whether it
    /// asks for the next one. It is worked out from where the wall is whenever the wall is
    /// drawn (`tracker`); a scroll changes nothing the wall is drawn from, so it writes its
    /// answer here when it is another, which draws the wall again.
    @State private var lastDrawn = ListPageSpans.Drawn()

    @Environment(\.openGallery) private var openGallery
    @Environment(\.look) private var look

    var body: some View {
        // Two scroll views, not one whose content is either form: the list is another one
        // when its pages come or go, and starts at its top.
        if let pages {
            let spans = ListPageSpans(
                pages: pages.sections, columns: layout.columns, rowHeight: layout.pitch,
                dividerHeight: style.texts.metrics.dividerHeight
            )
            scroll(pages: spans) { numbered(pages, spans: spans) }
        } else {
            scroll(pages: nil) { plain(input.feed.entries, phase: input.feed.phase) }
        }
    }

    /// - Parameter pages: where a numbered list's pages stand; `nil` for every other list.
    private func scroll(pages: ListPageSpans?, @ViewBuilder content: () -> some View) -> some View {
        let feed = input.feed
        let entries = feed.entries
        return ScrollView {
            content()
                // Entries that change inside someone else's animation (the find field closing)
                // take their places at once: what a lazy grid lays out must not be animated.
                .transaction(value: ListEntriesKey(entries)) { $0.animation = nil }
                .background { ScrollViewPinch(onStep: step) }
        }
        .scrollPosition($position)
        // Only the scale and the fade move, and only here: no animation may reach what the
        // lazy grid lays out.
        .animation(.snappy(duration: 0.25)) { $0.scaleEffect(cue.scale).opacity(cue.opacity) }
        .onScrollGeometryChange(for: WallListTracker.Place.self) { geometry in
            WallListTracker.Place(geometry)
        } action: { _, place in
            tracker.moved(to: place)
            guard let pages else { return }
            let drawn = tracker.drawn(of: pages)
            if drawn != lastDrawn { lastDrawn = drawn }
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

    /// A numbered list's pages: the first page's covers, then each later page under its
    /// divider, and the tiles of a page on its way.
    private func numbered(_ pages: RankedPages, spans: ListPageSpans) -> some View {
        // Worked out here, from where the wall is now: a page that arrived, or a density
        // change, is drawn with the pages that are near it at once. `lastDrawn` is read so
        // that a scroll's change draws the wall again, and follows what is drawn.
        let drawn = tracker.drawn(of: spans)
        let last = lastDrawn
        return VStack(alignment: .leading, spacing: 0) {
            // A child of the scroll view's content itself, so a first screen's scroll to its
            // top finds it, and at full width: a header brings its own margins.
            header
            VStack(alignment: .leading, spacing: 0) {
                top
                page(pages.first, number: nil, index: 0, of: spans, drawn: drawn)
                ForEach(pages.later) { later in
                    page(later.rows, number: later.number, index: later.index, of: spans, drawn: drawn)
                }
                if input.feed.footer == .loading {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 0) {
                        placeholders(layout.columns)
                    }
                }
                if drawn.asksForMore {
                    // The next page is asked for before the footer is reached (the footer
                    // asks too, should this not have): a scroll that goes on finds it there,
                    // as it did when one grid built its footer ahead.
                    Color.clear
                        .frame(height: 0)
                        .loadsNextPage(of: input.feed)
                }
                // As in `plain`: in a lazy stack of its own, and as high as the footer is at
                // least.
                LazyVStack(spacing: 0) {
                    footer(.content)
                }
                .frame(minHeight: Self.footerMinimum(.content), alignment: .top)
            }
            .padding(.horizontal, WallGridLayout.margin)
        }
        .coordinateSpace(.named(WallListSpace.name))
        // A page that becomes a grid or blank space inside someone else's animation does so
        // at once, as entries do.
        .transaction(value: drawn.pages) { $0.animation = nil }
        .onChange(of: drawn) { _, drawn in
            if drawn != last { lastDrawn = drawn }
        }
    }

    /// A page as a view of its own, which the wall drawn again leaves alone when nothing of
    /// the page changed (`WallListPage`).
    private func page(
        _ rows: ArraySlice<RankedEntry>, number: Int?, index: Int, of spans: ListPageSpans, drawn: ListPageSpans.Drawn
    ) -> some View {
        WallListPage(
            rows: rows, number: number, isNear: drawn.pages.contains(index), height: spans.height(ofPage: index),
            dividerHeight: spans.dividerHeight, layout: layout, style: style, selectedID: selectedID,
            actions: input.actions, prefetcher: prefetcher
        )
        .equatable()
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

/// The content's coordinate space, in which the top of the covers is measured.
nonisolated private enum WallListSpace {
    static let name = "WallListGrid"
}
