import EhCore
import EhFeatures
import EhModels
import SwiftUI

/// Ledger's list of galleries (`ledger.md` section 3): a plain `List` of dense rows, with a
/// cover or titles only (`ledgerShowsCovers`), headings for each day or page, and swipe
/// actions. It draws every list: Front Page, Popular, Watched, Toplists, History, a
/// favourites folder, search results.
///
/// `GalleryListScreen` calls it with `input` (`ListDesignInput`: the list's context, its
/// feed, its controls and the actions model) and the `header`, which is the first item of the
/// list and scrolls with the rows. The wrapper loads the list and presents what the controls
/// open; this view draws the rows, the states and the controls' places.
///
/// What only Ledger needs lives here as `@State` and goes with the view: the words of the
/// rows and the headings' layout, with the list's own cover prefetcher.
struct LedgerListView<Header: View>: View {
    let input: ListDesignInput
    @ViewBuilder var header: Header

    @State private var words = LedgerListWords()
    @State private var layout = LedgerListLayout()
    @State private var prefetcher = ListCoverPrefetcher()
    @State private var visits = LedgerListVisits()
    @Environment(SettingsStore.self) private var settings
    @Environment(FilterStore.self) private var filterStore
    @Environment(\.look) private var look

    var body: some View {
        let style = LedgerRowStyle(showsCover: settings.ledgerShowsCovers, look: look)
        content(style: style)
            .modifier(LedgerListChrome(
                input: input, ownFolder: input.ownFolder(hasHeader: hasHeader), showsCovers: showsCovers
            ))
            .onAppear {
                // Rows read their reading progress when their page is mapped; a gallery or a
                // reader opened from here may have moved it.
                if visits.hasLeft {
                    Task { await input.feed.refreshReadingProgress() }
                }
            }
            .onDisappear { visits.hasLeft = true }
    }

    @ViewBuilder
    private func content(style: LedgerRowStyle) -> some View {
        let feed = input.feed
        // A list under a header (a first screen's, the library's) keeps the header: its states
        // are rows (in `LedgerListContent`), without glass. Otherwise they take the screen,
        // where their buttons may be glass.
        switch (feed.phase, hasHeader) {
        case (.signedOut(let kind), false):
            ListSignInState(kind: kind)
                .background { look.background.ignoresSafeArea() }
        case (.failed(let error), false):
            ListFailedState(error: error, retry: feed.retry)
                .background { look.background.ignoresSafeArea() }
        case (.empty, false):
            emptyState
        default:
            LedgerListContent(
                input: input, header: header, style: style, words: words, layout: layout, prefetcher: prefetcher
            )
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if case .search(let keyword, _) = input.context.kind,
           !SearchLoosening.actions(for: keyword, filter: filterForLoosening).isEmpty {
            LedgerLooseningState(keyword: keyword, perform: input.perform)
        } else {
            ListEmptyState(message: L10n.Localizable.List.Empty.ledger, filters: input.filtersAction)
                .background { look.background.ignoresSafeArea() }
        }
    }

    /// A first screen or the library passes a header; a list of its own passes none.
    private var hasHeader: Bool { !(Header.self is EmptyView.Type) }

    /// The Search filter, which only a search's empty state reads.
    private var filterForLoosening: Filter {
        filterStore[.search]
    }

    private var showsCovers: Binding<Bool> {
        Binding(get: { settings.ledgerShowsCovers }, set: { settings.ledgerShowsCovers = $0 })
    }
}

/// Whether the list has been off screen since it first appeared.
private final class LedgerListVisits {
    var hasLeft = false
}

fileprivate extension ListDesignInput {
    /// Opens Filters when the list's filter narrows something; `nil` for the default filter
    /// and for a list without one.
    var filtersAction: (() -> Void)? {
        guard case .filter(let summary) = controls.primary, !summary.isDefault else { return nil }
        let perform = perform
        return { perform(.filters) }
    }
}

/// The list itself, under the header: placeholders, rows and the row after them.
private struct LedgerListContent<Header: View>: View {
    let input: ListDesignInput
    let header: Header
    let style: LedgerRowStyle
    let words: LedgerListWords
    let layout: LedgerListLayout
    let prefetcher: ListCoverPrefetcher

    /// What a row's More or Move swipe action opened.
    @State private var dialog: LedgerRowDialog?
    @Environment(\.openGallery) private var openGallery
    @Environment(StackRouter.self) private var stack
    @Environment(\.lookTint) private var tint
    @Environment(\.accessibilityVoiceOverEnabled) private var isVoiceOverOn

    private static var rowInsets: EdgeInsets {
        EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: LedgerGalleryRow.trailingInset)
    }
    private static var headingInsets: EdgeInsets { EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 16) }
    private static var placeholders: Int { 8 }

    var body: some View {
        let feed = input.feed
        let entries = feed.entries
        let kind = LedgerListKind(input.context)
        layout.update(entries, grouping: kind.grouping, pageStarts: feed.pageStarts, words: words)
        prefetcher.isEnabled = style.showsCover
        prefetcher.update(entries)
        let rows = LedgerRows(
            kind: kind, textInset: LedgerGalleryRow.textInset(showsCover: style.showsCover),
            selectedID: stack.sideGallery?.gid, isSpoken: ListSpokenRows.isOn(isVoiceOverOn)
        )
        return List {
            header
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            if let error = feed.staleError, error.isNetworkError {
                ListOfflineBanner(form: .line(L10n.Localizable.List.Offline.short), retry: feed.retry)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 4, trailing: 16))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
            switch feed.phase {
            case .loading:
                ForEach(0..<Self.placeholders, id: \.self) { _ in
                    LedgerSkeletonRow(style: style)
                        .listRowInsets(Self.rowInsets)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
            case .content:
                if layout.sections.isEmpty {
                    ForEach(entries) { entry in
                        row(entry, rank: nil, rows: rows)
                    }
                } else {
                    ForEach(layout.sections) { section in
                        LedgerHeadingRow(title: section.title, look: style.look)
                            .listRowInsets(Self.headingInsets)
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                        ForEach(entries[section.rows]) { entry in
                            row(entry, rank: rank(of: entry, in: section), rows: rows)
                        }
                    }
                }
                LedgerListFooter(feed: feed, style: style)
                    .loadsNextPage(of: feed)
                    .listRowInsets(Self.rowInsets)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            case .empty, .failed, .signedOut:
                // Only under a header; see `LedgerListView.content`.
                LedgerInlineState(phase: feed.phase, feed: feed, filters: input.filtersAction)
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background { style.look.background.ignoresSafeArea() }
        .refreshable { await feed.refresh() }
        .ledgerRowDialogs($dialog, actions: input.actions)
        .onDisappear { prefetcher.stop() }
    }

    /// One gallery's row, with what the list puts around it, in the order spike S1 measured:
    /// the tap, the insets and the separator, the swipe actions, the menu, the prefetch hook.
    /// Nothing around it depends on a condition.
    private func row(_ entry: GalleryEntry, rank: Int?, rows: LedgerRows) -> some View {
        let actions = input.actions
        let folder = rows.kind.marksFolders && !style.showsCover ? actions.favoriteFolder(of: entry) : nil
        let facts = words.facts(for: entry, ending: rows.kind.age, rank: rank)
        let spoken = rows.isSpoken ? words.spokenLine(for: entry, ending: rows.kind.age, rank: rank) : nil
        return Button {
            openGallery(entry.gallery)
        } label: {
            LedgerGalleryRow(entry: entry, facts: facts, spoken: spoken, folder: folder, style: style)
                .equatable()
        }
        .listRowInsets(Self.rowInsets)
        .alignmentGuide(.listRowSeparatorLeading) { _ in rows.textInset }
        // To the trailing edge, past the row's trailing inset, as drawn.
        .alignmentGuide(.listRowSeparatorTrailing) { $0[.trailing] + LedgerGalleryRow.trailingInset }
        .listRowBackground(entry.id == rows.selectedID ? tint.opacity(0.11) : style.look.background)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            LedgerSwipeActions(entry: entry, actions: actions, form: rows.kind.swipe) { dialog = $0 }
        }
        .galleryContextMenu(entry, actions: actions, offersMove: rows.kind.offersMove)
        .onAppear { prefetcher.appeared(entry.id) }
    }

    private func rank(of entry: GalleryEntry, in section: LedgerSection) -> Int? {
        guard let first = section.firstRank, let index = layout.index(of: entry.id) else { return nil }
        return first + index - section.rows.lowerBound
    }
}

/// What every row of one screen shares, made once per update of the list.
private struct LedgerRows {
    let kind: LedgerListKind
    let textInset: CGFloat
    /// The gallery in the side pane, whose row is tinted (iPad).
    let selectedID: String?
    /// VoiceOver is on: rows read their words in full (`LedgerListWords.spokenLine`).
    let isSpoken: Bool
}

/// What a kind of list changes in Ledger's rows.
nonisolated struct LedgerListKind: Equatable {
    var grouping: LedgerGrouping
    /// Which age ends the line of facts.
    var age: LedgerListWords.AgeKind
    var swipe: LedgerSwipeActions.Form
    /// Favourites: titles-only rows take the folder's colour, and the menu offers Move.
    var marksFolders: Bool

    var offersMove: Bool { marksFolders }

    init(_ context: ListContext) {
        switch context.kind {
        case .place(.frontpage), .place(.watched), .search, .scopedSearch(.watched, _), .scopedSearch(.everywhere, _):
            self.init(grouping: .days(.posted), age: .posted, swipe: .ordinary, marksFolders: false)
        case .place(.history):
            self.init(grouping: .days(.opened), age: .opened, swipe: .ordinary, marksFolders: false)
        case .place(.toplists):
            self.init(grouping: .pages, age: .posted, swipe: .ordinary, marksFolders: false)
        case .folder, .scopedSearch(.favorites, _), .place(.favorites):
            self.init(grouping: .none, age: .added, swipe: .folder, marksFolders: true)
        case .place(.popular):
            self.init(grouping: .none, age: .posted, swipe: .ordinary, marksFolders: false)
        }
    }

    init(grouping: LedgerGrouping, age: LedgerListWords.AgeKind, swipe: LedgerSwipeActions.Form, marksFolders: Bool) {
        self.grouping = grouping
        self.age = age
        self.swipe = swipe
        self.marksFolders = marksFolders
    }
}

/// The row after the last gallery: one placeholder row while the next page is on its way,
/// "Couldn't load more · Retry" when it failed, a little space at the end. One view in every
/// phase, so the next-page loader on it keeps its identity.
private struct LedgerListFooter: View {
    let feed: ListFeed
    let style: LedgerRowStyle

    var body: some View {
        switch feed.footer {
        case .more, .loading:
            LedgerSkeletonRow(style: style)
        case .failed:
            ListLoadMoreFailedRow { feed.retryNextPage() }
        case .end:
            Color.clear.frame(height: Tokens.Spacing.small)
        }
    }
}
