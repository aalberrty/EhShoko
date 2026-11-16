import EhCore
import EhFeatures
import EhModels
import SwiftUI

/// ADAPTER, deleted with the last list adapter (task I1).
///
/// Today's list, under the list part's contract: v3's rows or its grid of cards (by v3's
/// display mode), with the header as the first item of the lazy container, galleries opened
/// through `\.openGallery` with the row as the zoom's source, the controls in a More menu in
/// the top bar, and v3's states. The three list adapters show it until their designs are
/// built, so every surrounding can already be tried against a list that honours the contract.
struct V3ListBody<Header: View>: View {
    let input: ListDesignInput
    let header: Header

    @Environment(SettingsStore.self) private var settings

    var body: some View {
        content
            .refreshable { await input.feed.refresh() }
            .modifier(V3ListChrome(input: input))
    }

    @ViewBuilder
    private var content: some View {
        switch settings.listDisplayMode {
        case .detail: V3ListRows(input: input, header: header)
        case .thumbnail: V3ListGrid(input: input, header: header)
        }
    }
}

/// The title, the More menu and, for the lists that had one on v3, the field in the top bar.
private struct V3ListChrome: ViewModifier {
    let input: ListDesignInput

    @State private var keyword = ""
    @Environment(StackRouter.self) private var stack

    func body(content: Content) -> some View {
        let context = input.context
        if !context.showsTitle {
            // The first screen draws the title and the top bar's items.
            content
        } else {
            content
                .navigationTitle(title)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        ListMoreMenu(controls: input.controls.menu, perform: input.perform)
                    }
                }
                // In the top bar's drawer on both systems: at the bottom it would sit in the
                // chrome's place.
                .searchable(text: text, placement: .navigationBarDrawer(displayMode: .automatic), prompt: prompt)
                .onSubmit(of: .search) {
                    // A keyword searches the list's own scope, as a new list of results.
                    guard !input.controls.menu.find, !keyword.isEmpty else { return }
                    stack.push(SearchSurfaceModel.route(for: keyword, in: context.searchScope))
                }
        }
    }

    private var title: String {
        guard let period = input.controls.menu.period, let selection = period.selection,
              let option = period.options.first(where: { $0.id == selection })
        else { return input.context.title }
        return [input.context.title, option.title].joined(separator: " - ")
    }

    /// The lists whose field filtered the loaded titles on v3 keep that; the others search.
    private var text: Binding<String> {
        input.controls.menu.find
            ? Binding(get: { input.feed.findText }, set: { input.feed.findText = $0 })
            : $keyword
    }

    private var prompt: String {
        input.controls.menu.find
            ? L10n.Localizable.Searchable.Prompt.filter : L10n.Localizable.TabItem.Title.search
    }
}

private struct V3ListRows<Header: View>: View {
    let input: ListDesignInput
    let header: Header

    @Environment(\.openGallery) private var openGallery

    private var offersMove: Bool { input.context.signInKind == .favorites }

    var body: some View {
        List {
            header
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
            switch input.feed.phase {
            case .content:
                ForEach(input.feed.entries) { entry in
                    Button {
                        openGallery(entry.gallery)
                    } label: {
                        GalleryDetailRow(gallery: entry.gallery)
                            .zoomSource(entry.id)
                    }
                    .foregroundStyle(.primary)
                    .galleryContextMenu(entry, actions: input.actions, offersMove: offersMove)
                }
                V3ListFooter(feed: input.feed)
                    .listRowSeparator(.hidden)
            default:
                V3ListState(input: input)
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
    }
}

private struct V3ListGrid<Header: View>: View {
    let input: ListDesignInput
    let header: Header

    @Environment(\.openGallery) private var openGallery
    @Environment(\.horizontalSizeClass) private var sizeClass

    /// Legacy grid spacing.
    private static var spacing: CGFloat { 15 }

    private var offersMove: Bool { input.context.signInKind == .favorites }

    /// Two columns in compact width; as many as fit in regular width.
    private var columns: [GridItem] {
        if sizeClass == .regular {
            [GridItem(.adaptive(minimum: 180, maximum: GalleryThumbnailCell.maximumWidth), spacing: Self.spacing)]
        } else {
            Array(repeating: GridItem(.flexible(), spacing: Self.spacing), count: 2)
        }
    }

    var body: some View {
        ScrollView {
            header
            switch input.feed.phase {
            case .content:
                LazyVGrid(columns: columns, spacing: Self.spacing) {
                    Section {
                        ForEach(input.feed.entries) { entry in
                            Button {
                                openGallery(entry.gallery)
                            } label: {
                                GalleryThumbnailCell(gallery: entry.gallery)
                                    .zoomSource(entry.id)
                            }
                            .buttonStyle(.plain)
                            .galleryContextMenu(entry, actions: input.actions, offersMove: offersMove)
                        }
                    } footer: {
                        V3ListFooter(feed: input.feed)
                    }
                }
                .padding(.horizontal, Tokens.Spacing.large)
                .padding(.vertical, Tokens.Spacing.small)
            default:
                V3ListState(input: input)
            }
        }
    }
}

/// v3's states, as one item under the header.
private struct V3ListState: View {
    let input: ListDesignInput

    var body: some View {
        Group {
            switch input.feed.phase {
            case .signedOut:
                LoginRequiredView()
            case .loading:
                LoadingStateView()
            case .empty:
                EmptyStateView()
            case .failed(let error):
                ErrorStateView(error: error, retry: error.isRetryable ? { input.feed.retry() } : nil)
            case .content:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity, minHeight: 360)
    }
}

private struct V3ListFooter: View {
    let feed: ListFeed

    var body: some View {
        PaginationFooter(phase: phase) { feed.retryNextPage() }
            .loadsNextPage(of: feed)
    }

    private var phase: PaginationFooter.Phase {
        switch feed.footer {
        case .more: .idle
        case .loading: .loading
        case .failed: .failed
        case .end: .end
        }
    }
}
