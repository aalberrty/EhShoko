import EhFeatures
import EhModels
import SwiftUI

/// One column: a plain `List`, the header as its first row, then the filter or sort line, the
/// offline banner, the rows and the footer row.
///
/// Inside each `ForEach` the row and its modifiers are written out without a condition
/// (`spikes/S1.md`, rule 1): with one, the list would walk its rows from the start of the
/// section for every row it sets up. What differs between lists is decided around the
/// `ForEach`es: Toplists' pages each get one, after their divider.
struct ShelfListRows<Header: View>: View {
    let input: ListDesignInput
    let header: Header
    let style: ShelfRowStyle
    let headerLine: ListPrimaryControl?
    let prefetcher: ShelfListPrefetcher

    @Environment(\.openGallery) private var openGallery
    @Environment(\.look) private var look

    var body: some View {
        let feed = input.feed
        let entries = feed.entries
        List {
            // A direct row of the list, so a first screen's scroll to its top finds it.
            header
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            if let headerLine {
                ShelfListHeaderLine(control: headerLine, perform: input.perform)
                    .listRowInsets(ShelfListLayout.lineInsets)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
            switch feed.phase {
            case .loading:
                ForEach(0..<ShelfListPlaceholderRow.count, id: \.self) { _ in
                    ShelfListPlaceholderRow(style: style)
                        .listRowInsets(ShelfListLayout.insets(isRanked: style.isRanked))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
            case .content:
                if feed.staleError?.isNetworkError == true {
                    ListOfflineBanner(form: .line(nil)) { feed.retry() }
                        .listRowInsets(ShelfListLayout.bannerInsets)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
                if style.isRanked {
                    rankedRows(ShelfRankedPages(entries: entries, pageStarts: feed.pageStarts, findText: feed.findText))
                } else {
                    rows(entries[...])
                }
                ShelfListFooterRow(footer: feed.footer, retry: feed.retryNextPage)
                    .loadsNextPage(of: feed)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            case .signedOut, .empty, .failed:
                // Under a header: the state below it, as `shelf.md` asks for Home.
                ShelfListState(input: input)
                    .frame(minHeight: ShelfListLayout.stateHeight)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(look.background)
        .refreshable { await feed.refresh() }
        .onChange(of: ShelfListPrefetchKey(entries), initial: true) { prefetcher.update(entries) }
    }

    private func rows(_ entries: ArraySlice<GalleryEntry>) -> some View {
        let textInset = ShelfGalleryRow.textInset(isRanked: false)
        let offersMove = input.context.signInKind == .favorites
        return ForEach(entries) { entry in
            Button {
                openGallery(entry.gallery)
            } label: {
                ShelfGalleryRow(entry: entry, style: style).equatable()
            }
            .foregroundStyle(.primary)
            .listRowInsets(ShelfListLayout.rowInsets)
            .listRowSeparatorTint(look.separator)
            .listRowBackground(Color.clear)
            .alignmentGuide(.listRowSeparatorLeading) { _ in textInset }
            .galleryContextMenu(entry, actions: input.actions, offersMove: offersMove)
            .onAppear { prefetcher.appeared(entry.id) }
        }
    }

    @ViewBuilder
    private func rankedRows(_ pages: ShelfRankedPages) -> some View {
        rankedRows(pages.first)
        ForEach(pages.later) { page in
            ShelfListPageDivider(page: page.number)
                .listRowInsets(ShelfListLayout.dividerInsets)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            rankedRows(page.rows)
        }
    }

    private func rankedRows(_ rows: ArraySlice<ShelfRankedEntry>) -> some View {
        let textInset = ShelfGalleryRow.textInset(isRanked: true)
        return ForEach(rows) { row in
            Button {
                openGallery(row.entry.gallery)
            } label: {
                ShelfGalleryRow(entry: row.entry, rank: row.rank, style: style).equatable()
            }
            .foregroundStyle(.primary)
            .listRowInsets(ShelfListLayout.rankedInsets)
            .listRowSeparatorTint(look.separator)
            .listRowBackground(Color.clear)
            .alignmentGuide(.listRowSeparatorLeading) { _ in textInset }
            .galleryContextMenu(row.entry, actions: input.actions)
            .onAppear { prefetcher.appeared(row.entry.id) }
        }
    }
}

/// What tells the prefetcher that the rows changed: another first row (another list, or the
/// rows narrowed by Find), or more rows.
struct ShelfListPrefetchKey: Equatable {
    let first: String?
    let count: Int

    init(_ entries: [GalleryEntry]) {
        first = entries.first?.id
        count = entries.count
    }
}

/// A Toplists row with its rank.
struct ShelfRankedEntry: Identifiable {
    let entry: GalleryEntry
    /// 1-based; `nil` while Find narrows the rows, when a row's rank is not known.
    let rank: Int?

    var id: String { entry.id }
}

/// Toplists' rows by the page they came from: the first page's rows, then each later page
/// with its number for the "Page 2" divider. Ranks count from the page's number, so a list
/// opened at page 5 starts at 201.
struct ShelfRankedPages {
    struct Page: Identifiable {
        let number: Int
        let rows: ArraySlice<ShelfRankedEntry>

        var id: Int { number }
    }

    let first: ArraySlice<ShelfRankedEntry>
    let later: [Page]

    init(entries: [GalleryEntry], pageStarts: [PageStart], findText: String) {
        guard let start = pageStarts.first else {
            // Popular (one page), or Find narrowing the rows: no pages to tell apart.
            let ranks = findText.isEmpty
            first = entries.enumerated().map { ShelfRankedEntry(entry: $1, rank: ranks ? $0 + 1 : nil) }[...]
            later = []
            return
        }
        let pageSize = pageStarts.count > 1
            ? pageStarts[1].index - start.index : ShelfListLayout.rankedPageSize
        var rows: [ShelfRankedEntry] = []
        rows.reserveCapacity(entries.count)
        // Where each page's rows are in `rows`.
        var bounds: [(number: Int, range: Range<Int>)] = []
        for (offset, page) in pageStarts.enumerated() {
            let end = offset + 1 < pageStarts.count ? pageStarts[offset + 1].index : entries.count
            let lower = min(page.index, entries.count)
            let base = (page.page - 1) * pageSize + 1
            let rowsStart = rows.count
            for index in lower..<max(min(end, entries.count), lower) {
                rows.append(ShelfRankedEntry(entry: entries[index], rank: base + index - lower))
            }
            bounds.append((page.page, rowsStart..<rows.count))
        }
        first = rows[bounds.first?.range ?? 0..<0]
        later = bounds.dropFirst().map { Page(number: $0.number, rows: rows[$0.range]) }
    }
}
