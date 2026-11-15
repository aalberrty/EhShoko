import EhFeatures
import EhModels
import SwiftUI

/// Two or three columns, on a container 700 pt wide or more (`shelf.md` section 3): a lazy grid
/// of the same rows, which keep their form. Shelf has no swipe actions, so a grid loses nothing.
///
/// The header is the header of the grid's first section, so it spans the columns and stays a
/// direct item of the lazy container; the filter line and the offline banner head the rows'
/// section, Toplists' later pages are sections of their own under their divider, and the
/// footer row closes the last section.
struct ShelfListGrid<Header: View>: View {
    let input: ListDesignInput
    let header: Header
    let style: ShelfRowStyle
    let columns: Int
    let headerLine: ListPrimaryControl?
    let prefetcher: ShelfListPrefetcher

    @Environment(\.openGallery) private var openGallery
    @Environment(\.look) private var look

    var body: some View {
        let feed = input.feed
        let entries = feed.entries
        let phase = feed.phase
        let pages: ShelfRankedPages? = style.isRanked && phase == .content
            ? ShelfRankedPages(entries: entries, pageStarts: feed.pageStarts, findText: feed.findText) : nil
        ScrollView {
            LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 0) {
                Section {} header: { header }
                Section {
                    switch phase {
                    case .loading:
                        ForEach(0..<ShelfListPlaceholderRow.count, id: \.self) { _ in
                            ShelfListPlaceholderRow(style: style)
                                .padding(ShelfListLayout.insets(isRanked: style.isRanked))
                        }
                    case .content:
                        if let pages {
                            rankedCells(pages.first)
                        } else {
                            cells(entries[...])
                        }
                    case .signedOut, .empty, .failed:
                        EmptyView()
                    }
                } header: {
                    VStack(alignment: .leading, spacing: 0) {
                        if let headerLine {
                            ShelfListHeaderLine(control: headerLine, perform: input.perform)
                                .padding(ShelfListLayout.lineInsets)
                        }
                        if phase == .content, feed.staleError?.isNetworkError == true {
                            ListOfflineBanner(form: .line(nil)) { feed.retry() }
                                .padding(ShelfListLayout.bannerInsets)
                        }
                    }
                }
                if let pages {
                    ForEach(pages.later) { page in
                        Section {
                            rankedCells(page.rows)
                        } header: {
                            ShelfListPageDivider(page: page.number)
                                .padding(ShelfListLayout.dividerInsets)
                        }
                    }
                }
                Section {} footer: {
                    footer(phase: phase)
                }
            }
            .padding(.horizontal, ShelfListLayout.gridSpacing / 2)
        }
        .background(look.background)
        .refreshable { await feed.refresh() }
        .onChange(of: ShelfListPrefetchKey(entries), initial: true) { prefetcher.update(entries) }
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
            ShelfListState(input: input)
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

    private func rankedCells(_ rows: ArraySlice<ShelfRankedEntry>) -> some View {
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
