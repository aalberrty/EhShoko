#if DEBUG
import EhFeatures
import EhModels
import SwiftUI

/// The screen under the dock: the list with the long-press menu, or one of the state pieces.
struct DockHarnessPage: View {
    @Binding var setup: DockHarnessSetup
    let entries: [GalleryEntry]
    let actions: GalleryActionsModel
    @Binding var titleFilter: String
    @Environment(\.look) private var look

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(look.background)
            .navigationTitle(Text(verbatim: "Dock harness"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .listFindBar(isPresented: $setup.showsFind, text: $titleFilter)
            // What the shell's wrapper will apply to every screen: the chrome's height kept
            // free inside the screen (`spikes/S2.md` section 1.5).
            .bottomBar { Color.clear.frame(height: setup.page == .dock ? 44 : 0) }
    }

    @ViewBuilder
    private var content: some View {
        switch setup.page {
        case .dock:
            List(entries) { entry in
                DockHarnessRow(entry: entry)
                    .galleryContextMenu(entry, actions: actions, offersMove: entry.favorite != nil)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        case .states:
            DockHarnessStates()
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            DockHarnessOptions(setup: $setup)
        }
        ToolbarItem(placement: .primaryAction) {
            ListMoreMenu(controls: Self.controls) { action in
                if action == .find { setup.showsFind = true }
            } form: {
                Button(L10n.Localizable.List.Density.medium, systemImage: "square.grid.3x3") {}
            }
        }
    }

    private static let controls: ListMenuControls = {
        var filter = Filter()
        filter.doujinshi = true
        filter.western = true
        filter.advanced = true
        filter.minRatingActivated = true
        filter.minRating = 3
        let periods = ["Popular", "Yesterday", "Past month", "Past year", "All time"]
        return ListMenuControls(
            filterSummary: FilterSummary(filter),
            period: ListMenuPicker(
                title: L10n.Localizable.ToplistsView.Title.toplists, systemImage: "calendar",
                options: periods.enumerated().map { ListMenuPicker.Option(id: $0.offset, title: $0.element) },
                selection: 1
            ),
            page: ListMenuPage(title: "Yesterday", current: 1, maximum: 200),
            quickSearch: true, find: true, clear: true, reload: true
        )
    }()
}

/// A plain row: the cover and the parsed title. It reads nothing but its entry and the look.
private struct DockHarnessRow: View, Equatable {
    let entry: GalleryEntry
    @Environment(\.look) private var look

    var body: some View {
        HStack(alignment: .top, spacing: Tokens.Spacing.medium) {
            CoverImage(url: entry.gallery.coverURL, size: CGSize(width: 54, height: 77), cornerRadius: 5)
            VStack(alignment: .leading, spacing: Tokens.Spacing.xSmall) {
                if let credit = entry.title.credit {
                    Text(credit)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(look.secondaryLabel)
                        .lineLimit(1)
                }
                Text(entry.title.core)
                    .font(.callout.weight(.semibold))
                    .fontDesign(look.titleDesign)
                    .foregroundStyle(look.label)
                    .lineLimit(2)
                HStack(spacing: Tokens.Spacing.small) {
                    CategoryMark(entry.gallery.category, style: .name)
                    if entry.favorite != nil {
                        Image(systemName: "heart.fill").foregroundStyle(look.secondaryLabel)
                    }
                }
                .font(.caption)
            }
        }
        .listRowBackground(Color.clear)
    }

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.entry == rhs.entry }
}

/// The bottom chrome as the shell will host it: one glass container, the namespace the slots
/// morph in, the dock's or the bar's shapes.
struct DockHarnessChrome: View {
    @Binding var setup: DockHarnessSetup
    @Namespace private var glass

    var body: some View {
        GlassGroup(spacing: ActionDock.spacing) {
            ZStack {
                if setup.variant == .bar {
                    DockHarnessBar()
                } else {
                    ActionDock(content: DockHarnessContent.content(for: setup), perform: perform)
                }
            }
            .frame(maxWidth: 560)
            .frame(height: ActionDock.height)
        }
        .padding(.horizontal, Tokens.Spacing.medium)
        .padding(.bottom, -Tokens.Spacing.small)
        .environment(\.chromeNamespace, glass)
    }

    private func perform(_ action: DockAction) {
        withAnimation(.smooth(duration: 0.3)) {
            switch action {
            case .favorite, .favoriteIn:
                setup.isFavorite = true
            case .unfavorite:
                setup.isFavorite = false
            case .read:
                if let progress = setup.progress {
                    setup.progress = progress >= 48 ? nil : progress + 1
                } else {
                    setup.progress = 1
                }
            case .comments:
                setup.variant = .comments
            default:
                break
            }
        }
    }
}

/// The command bar's three shapes in the bar's slots, so switching to a dock shows the morph.
private struct DockHarnessBar: View {
    @Environment(\.look) private var look

    var body: some View {
        HStack(spacing: ActionDock.spacing) {
            Label { Text(verbatim: "Front Page") } icon: { Image(systemName: "house") }
                .font(.body.weight(.semibold))
                .fixedSize()
                .padding(.horizontal, Tokens.Spacing.large)
                .frame(height: ActionDock.height)
                .chromeShape(.leading, in: .capsule)
            Label { Text(verbatim: "Search") } icon: { Image(systemName: "magnifyingglass") }
                .foregroundStyle(look.secondaryLabel)
                .frame(maxWidth: .infinity, minHeight: ActionDock.height, alignment: .leading)
                .padding(.horizontal, Tokens.Spacing.large)
                .chromeShape(.centre, in: .capsule)
            Image(systemName: "line.3.horizontal.decrease")
                .font(.title3)
                .frame(width: ActionDock.height, height: ActionDock.height)
                .chromeShape(.trailing, in: .circle)
        }
        .foregroundStyle(look.label)
    }
}

/// The docks the three gallery designs and Comments declare (`shelf.md`, `wall.md`,
/// `ledger.md` section 4), built as a design would build them.
enum DockHarnessContent {
    static func content(for setup: DockHarnessSetup) -> DockContent {
        let favorite = DockItem(
            title: setup.isFavorite ? L10n.Localizable.List.Action.unfavorite : L10n.Localizable.List.Action.favorite,
            systemImage: setup.isFavorite ? "heart.fill" : "heart",
            action: setup.isFavorite ? .unfavorite : .favorite,
            menu: folderMenu(current: setup.isFavorite ? 3 : nil)
        )
        let comments = DockItem(
            title: L10n.Localizable.CommentsView.Title.comments, systemImage: "bubble.left.and.bubble.right",
            action: .comments
        )
        switch setup.variant {
        case .shelf, .bar:
            return DockContent(
                leading: favorite, primary: read(setup.progress, short: false), trailing: .button(comments),
                anchorsFavoriteTip: true
            )
        case .wall:
            let more = DockMenu([
                DockMenuEntry(title: L10n.Localizable.CommentsView.Title.comments, systemImage: "bubble.left.and.bubble.right", action: .comments),
                DockMenuEntry(title: L10n.Localizable.GalleryInfosView.Title.galleryInfos, systemImage: "info.circle", action: .galleryInfos),
                DockMenuEntry(title: L10n.Localizable.Gallery.Action.similar, systemImage: "square.on.square", action: .similarGalleries),
                DockMenuEntry(title: L10n.Localizable.Gallery.Action.archive, systemImage: "doc.zipper", action: .archive),
                DockMenuEntry(title: L10n.Localizable.Gallery.Action.torrents, systemImage: "leaf", action: .torrents),
            ])
            return DockContent(
                leading: favorite, primary: read(setup.progress, short: true),
                trailing: .menu(title: L10n.Localizable.List.Action.more, systemImage: "ellipsis", menu: more),
                anchorsFavoriteTip: true
            )
        case .ledger:
            let rate = DockItem(title: L10n.Localizable.Gallery.Action.rate, systemImage: "star", action: .rate)
            return DockContent(
                leading: favorite, primary: read(setup.progress, short: false), trailing: .buttons([rate, comments]),
                anchorsFavoriteTip: true
            )
        case .comments:
            return .pill(DockItem(title: L10n.Localizable.Gallery.Comments.write, action: .writeComment))
        }
    }

    private static func read(_ progress: Int?, short: Bool) -> DockItem {
        guard let progress else { return DockItem(title: L10n.Localizable.Gallery.read, action: .read) }
        let detail = short
            ? L10n.Localizable.Gallery.Continue.short(progress, 48)
            : L10n.Localizable.Gallery.Continue.page(progress, 48)
        return DockItem(
            title: L10n.Localizable.Gallery.continue, detail: detail, systemImage: short ? "play.fill" : nil,
            action: .read
        )
    }

    private static func folderMenu(current: Int?) -> DockMenu {
        var sections = [
            DockMenuSection(entries: FavoriteReport.folders.map { index in
                DockMenuEntry(title: "Favorites \(index)", action: .favoriteIn(folder: index), isSelected: index == current)
            }),
        ]
        if current != nil {
            sections.append(DockMenuSection(entries: [
                DockMenuEntry(
                    title: L10n.Localizable.List.Action.unfavorite, systemImage: "heart.slash", action: .unfavorite,
                    isDestructive: true
                ),
            ]))
        }
        return DockMenu(sections: sections)
    }
}

/// The harness's own settings: look, appearance, page, dock, find bar, sheet.
private struct DockHarnessOptions: View {
    @Binding var setup: DockHarnessSetup

    var body: some View {
        Menu {
            Picker(selection: $setup.look) {
                ForEach(Look.allCases, id: \.self) { Text(verbatim: String(describing: $0).capitalized).tag($0) }
            } label: { Text(verbatim: "Look") }
            Picker(selection: $setup.scheme) {
                Text(verbatim: "System").tag(ColorScheme?.none)
                Text(verbatim: "Light").tag(ColorScheme?.some(.light))
                Text(verbatim: "Dark").tag(ColorScheme?.some(.dark))
            } label: { Text(verbatim: "Appearance") }
            Picker(selection: $setup.page) {
                ForEach(DockHarnessSetup.Page.allCases) { Text(verbatim: $0.rawValue.capitalized).tag($0) }
            } label: { Text(verbatim: "Page") }
            Picker(selection: Binding(
                get: { setup.variant },
                set: { variant in withAnimation(.smooth(duration: 0.4)) { setup.variant = variant } }
            )) {
                ForEach(DockHarnessSetup.Variant.allCases) { Text(verbatim: $0.rawValue.capitalized).tag($0) }
            } label: { Text(verbatim: "Dock") }
            Toggle(isOn: $setup.showsSheet) { Text(verbatim: "In a sheet") }
        } label: {
            Label { Text(verbatim: "Options") } icon: { Image(systemName: "slider.horizontal.3") }
        }
    }
}

/// The state pieces, one at a time: they fill the screen, and their buttons are glass, so they
/// do not scroll.
private struct DockHarnessStates: View {
    enum Kind: String, CaseIterable, Identifiable {
        case signIn, empty, failed, rows
        var id: String { rawValue }
    }

    @State private var kind = UserDefaults.standard.string(forKey: "HarnessState").flatMap(Kind.init(rawValue:)) ?? .signIn

    var body: some View {
        Group {
            switch kind {
            case .signIn:
                ListSignInState(kind: .watched)
            case .empty:
                ListEmptyState(filters: {})
            case .failed:
                ListFailedState(error: .networkingFailed, retry: {}, openHistory: {})
            case .rows:
                List {
                    ListOfflineBanner(form: .line(nil)) {}
                    ListOfflineBanner(form: .line(L10n.Localizable.List.Offline.short)) {}
                    ListOfflineBanner(form: .card) {}
                    ListLoadMoreFailedRow {}
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .topBar {
            Picker(selection: $kind) {
                ForEach(Kind.allCases) { Text(verbatim: $0.rawValue).tag($0) }
            } label: { Text(verbatim: "State") }
            .pickerStyle(.segmented)
            .padding(.horizontal, Tokens.Spacing.large)
            .padding(.vertical, Tokens.Spacing.small)
        }
    }
}
#endif
