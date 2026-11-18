import EhFeatures
import EhModels
import SwiftUI

/// Two or three columns, on a container 700 pt wide or more (`shelf.md` section 3): a lazy grid
/// of the same rows, which keep their form. Shelf has no swipe actions, so a grid loses nothing.
///
/// The grid holds the rows, and they are its own items, not a section's content: a lazy grid
/// whose cells are a `Section`'s content builds rows at twice the scroll offset while a
/// finger scrolls it, cells nobody sees that are built once more when their turn comes. The
/// header, the filter line and the offline banner stand before the grid and the footer row
/// after it, in the stack around it.
///
/// Toplists' pages keep the form all lists had (`numbered`): one grid whose sections are the
/// pages, each under its divider, with the header, the filter line and the footer row as
/// sections of their own; its cells are built ahead as described. The dividers have to be
/// among the grid's rows, and as headers of sections that hold nothing, with the cells as
/// the grid's items, the grid on iOS 18 ends before its last row.
struct ShelfListGrid<Header: View>: View {
    let input: ListDesignInput
    let header: Header
    let style: ShelfRowStyle
    let columns: Int
    let headerLine: ListPrimaryControl?
    let prefetcher: ListCoverPrefetcher

    @Environment(\.openGallery) private var openGallery
    @Environment(\.look) private var look

    var body: some View {
        let feed = input.feed
        let entries = feed.entries
        let phase = feed.phase
        ScrollView {
            Group {
                if style.isRanked, phase == .content {
                    numbered(RankedPages(entries: entries, pageStarts: feed.pageStarts, findText: feed.findText))
                } else {
                    plain(entries, phase: phase)
                }
            }
            .padding(.horizontal, ShelfListLayout.gridSpacing / 2)
        }
        .background(look.background)
        .refreshable { await feed.refresh() }
        .onChange(of: ListEntriesKey(entries), initial: true) { prefetcher.update(entries) }
    }

    /// The filter line and the offline banner, which head the rows.
    private func heading(phase: ListFeed.Phase) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let headerLine {
                ShelfListHeaderLine(control: headerLine, perform: input.perform)
                    .padding(ShelfListLayout.lineInsets)
            }
            if phase == .content, input.feed.staleError?.isNetworkError == true {
                ListOfflineBanner(form: .line(nil)) { input.feed.retry() }
                    .padding(ShelfListLayout.bannerInsets)
            }
        }
    }

    /// Every list but Toplists with its pages: the rows alone in the grid.
    private func plain(_ entries: [GalleryEntry], phase: ListFeed.Phase) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // A child of the scroll view's content itself, so a first screen's scroll to its
            // top finds it.
            header
            heading(phase: phase)
            LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 0) {
                switch phase {
                case .loading:
                    ForEach(0..<ShelfListPlaceholderRow.count, id: \.self) { _ in
                        ShelfListPlaceholderRow(style: style)
                            .padding(ShelfListLayout.insets(isRanked: style.isRanked))
                    }
                case .content:
                    cells(entries[...])
                case .signedOut, .empty, .failed:
                    EmptyView()
                }
            }
            // In a lazy stack of its own: the footer row asks for the next page when it
            // appears, which in the plain stack around it would be at once. The stack is as
            // high as the footer is at least, so that it is reached: on iOS 18 a lazy stack
            // that has built nothing has no height, and one at the very end of the content
            // never came on screen.
            LazyVStack(spacing: 0) {
                footer(phase: phase)
            }
            .frame(minHeight: Self.footerMinimum(phase), alignment: .top)
        }
    }

    /// Toplists' pages, in the form all lists had: sections of one grid.
    private func numbered(_ pages: RankedPages) -> some View {
        LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 0) {
            Section {} header: { header }
            Section {
                rankedCells(pages.first)
            } header: {
                heading(phase: .content)
            }
            ForEach(pages.later) { page in
                Section {
                    rankedCells(page.rows)
                } header: {
                    ShelfListPageDivider(page: page.number)
                        .padding(ShelfListLayout.dividerInsets)
                }
            }
            Section {} footer: {
                footer(phase: .content)
            }
        }
    }

    /// The least the footer of a phase is high.
    private static func footerMinimum(_ phase: ListFeed.Phase) -> CGFloat {
        switch phase {
        case .content: ShelfListFooterRow.minimumHeight
        case .signedOut, .empty, .failed: ShelfListLayout.stateHeight
        case .loading: 0
        }
    }

    private var gridColumns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(), spacing: ShelfListLayout.gridSpacing, alignment: .top),
            count: columns
        )
    }

    @ViewBuilder
    private func footer(phase: ListFeed.Phase) -> some View {
        switch phase {
        case .content:
            ShelfListFooterRow(footer: input.feed.footer, retry: input.feed.retryNextPage)
                .loadsNextPage(of: input.feed)
        case .signedOut, .empty, .failed:
            // Under a header, in the scroll view: its buttons are filled, not glass.
            ShelfListState(input: input)
                .statusActionForm(.filled)
                .frame(maxWidth: .infinity, minHeight: ShelfListLayout.stateHeight)
        case .loading:
            EmptyView()
        }
    }

    private func cells(_ entries: ArraySlice<GalleryEntry>) -> some View {
        let offersMove = input.context.signInKind == .favorites
        return ForEach(entries) { entry in
            Button {
                openGallery(entry.gallery)
            } label: {
                ShelfGalleryRow(entry: entry, style: style).equatable()
                    .padding(ShelfListLayout.rowInsets)
                    .overlay(alignment: .bottomTrailing) { separator(isRanked: false) }
            }
            .buttonStyle(.plain)
            .galleryContextMenu(entry, actions: input.actions, offersMove: offersMove)
            .onAppear { prefetcher.appeared(entry.id) }
        }
    }

    private func rankedCells(_ rows: ArraySlice<RankedEntry>) -> some View {
        ForEach(rows) { row in
            Button {
                openGallery(row.entry.gallery)
            } label: {
                ShelfGalleryRow(entry: row.entry, rank: row.rank, style: style).equatable()
                    .padding(ShelfListLayout.rankedInsets)
                    .overlay(alignment: .bottomTrailing) { separator(isRanked: true) }
            }
            .buttonStyle(.plain)
            .galleryContextMenu(row.entry, actions: input.actions)
            .onAppear { prefetcher.appeared(row.entry.id) }
        }
    }

    /// The hairline under a cell, from where its text starts, as the list draws it.
    private func separator(isRanked: Bool) -> some View {
        let insets = ShelfListLayout.insets(isRanked: isRanked)
        return look.separator
            .frame(height: 0.5)
            .padding(.leading, insets.leading + ShelfGalleryRow.textInset(isRanked: isRanked))
            .accessibilityHidden(true)
    }
}
