import Dependencies
import EhCore
import EhFeatures
import EhModels
import SwiftUI

private typealias Action = L10n.Localizable.Gallery.Action

/// Ledger's gallery page (`ledger.md` section 4): it reads like a document. The header, a
/// ruled table of facts, the tags as text and a strip of previews, with Share and More in the
/// top bar and Favourite, Read and Comments in the dock.
///
/// Pushed, in the side pane (`chrome.isSidePane`, where the shell adds Close) or in the gallery
/// sheet (`chrome.isSheet`). What every gallery design shares is `GalleryPage`'s: the load, the
/// child screens it pushes, the sheets, the reader. This page draws the model, declares its
/// dock and sets the model's destination.
///
/// States, as Shelf's page: the header is drawn at once from the list's data and the table
/// holds ruled blanks until the page arrives; a failed load keeps the header with the error
/// below it; a stored page that could not be refreshed shows a banner under the header.
struct LedgerGalleryView: View {
    let model: GalleryDetailModel

    @Environment(SettingsStore.self) private var settings
    @Environment(UserStore.self) private var userStore
    @Environment(StackRouter.self) private var stack: StackRouter?
    @Environment(AppRouter.self) private var appRouter: AppRouter?
    @Environment(\.chrome) private var chrome
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.look) private var look
    @Dependency(\.clipboardClient) private var clipboard

    @State private var titles: LedgerGalleryTitles?
    @State private var hud: HUDConfiguration?
    @State private var copyCount = 0
    @State private var searchCount = 0

    /// The facts table's place in the scroll view, for Rate from the top bar or the dock.
    private static let factsID = "facts"

    var body: some View {
        let source = LedgerGalleryTitles.source(of: model, prefersJapanese: settings.displaysJapaneseTitle)
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    LedgerGalleryHeader(
                        coverURL: model.gallery.coverURL ?? model.detail?.coverURL,
                        category: model.detail?.category ?? model.gallery.category,
                        titles: titles ?? .unparsed(source), search: search, copy: copy
                    )
                    .equatable()
                    .padding(.top, 6)
                    sections
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 28)
            }
            .toolbar { toolbar(rate: { rate(proxy) }) }
            .dock(dock) { perform($0, rate: { rate(proxy) }) }
        }
        .background { look.background.ignoresSafeArea() }
        .navigationBarTitleDisplayMode(.inline)
        .hud($hud)
        .task(id: source) {
            titles = await LedgerGalleryTitles.make(source, gallery: model.gallery)
        }
        .onChange(of: model.favoriteReport) { _, report in
            guard let report else { return }
            hud = .symbol("heart.fill", title: L10n.Localizable.List.Favorited.hud(userStore.favoriteFolderName(report.folder)))
            FavoriteTip.record(report)
        }
        .sensoryFeedback(.success, trigger: copyCount)
        .sensoryFeedback(.impact(flexibility: .soft), trigger: searchCount)
    }

    // MARK: Content

    @ViewBuilder
    private var sections: some View {
        if model.detail == nil, let error = model.loadingState.failed {
            ErrorStateView(error: error, retry: error.isRetryable ? { model.refetch() } : nil)
                .frame(maxWidth: .infinity)
                .padding(.top, 48)
        } else {
            if model.detail != nil, let error = model.loadingState.failed {
                LedgerGalleryBanner(error: error) { model.refetch() }
                    .padding(.top, 16)
            }
            LedgerGalleryFacts(
                values: LedgerGalleryFacts.Values(
                    detail: model.detail, readingProgress: model.readingProgress, tags: model.tagRows.map(\.tag)
                ),
                rating: rating, searchUploader: searchUploader
            )
            .equatable()
            .id(Self.factsID)
            .padding(.top, 18)
            LedgerGalleryTags(model: model)
                .padding(.top, 22)
            LedgerGalleryPreviews(model: model)
                .padding(.top, 22)
        }
    }

    private var rating: LedgerGalleryFacts.Rating? {
        guard model.isLoggedIn else { return nil }
        return LedgerGalleryFacts.Rating(
            isPresented: model.showsRatingControl, halfStars: model.userRating,
            present: { if !model.showsRatingControl { model.toggleRatingControl() } },
            dismiss: { if model.showsRatingControl { model.toggleRatingControl() } },
            commit: { model.rate($0) }
        )
    }

    // MARK: Top bar

    @ToolbarContentBuilder
    private func toolbar(rate: @escaping () -> Void) -> some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            if let url = model.gallery.galleryURL {
                ShareLink(item: url) {
                    Label(L10n.Localizable.DetailView.ToolbarItem.Button.share, systemImage: "square.and.arrow.up")
                }
            }
            Menu {
                moreMenu(rate: rate)
            } label: {
                Label(L10n.Localizable.List.Action.more, systemImage: "ellipsis")
            }
            .menuOrder(.fixed)
        }
    }

    /// Rate, Archive, Torrents, Gallery infos, Similar galleries.
    @ViewBuilder
    private func moreMenu(rate: @escaping () -> Void) -> some View {
        let hasPage = model.detail != nil
        Button(Action.rate, systemImage: "star", action: rate)
            .disabled(!model.isLoggedIn || !hasPage)
        Button(Action.archive, systemImage: "doc.zipper") { model.showArchives() }
            .disabled(!model.canOpenArchives)
        Button(
            model.torrentCount > 0 ? Action.Torrents.count(model.torrentCount) : Action.torrents, systemImage: "leaf"
        ) { model.showTorrents() }
        .disabled(model.torrentCount == 0)
        Button(L10n.Localizable.GalleryInfosView.Title.galleryInfos, systemImage: "info.circle") {
            model.destination = .galleryInfos
        }
        .disabled(!hasPage)
        Button(Action.similar, systemImage: "photo.on.rectangle.angled") {
            if let keyword = model.similarGalleryKeyword { search(keyword) }
        }
        .disabled(model.similarGalleryKeyword == nil)
    }

    // MARK: Dock

    private var dock: DockContent {
        LedgerGalleryDock.content(
            model: model, showsRate: sizeClass == .regular || chrome.isSidePane,
            folderName: userStore.favoriteFolderName
        )
    }

    private func perform(_ action: DockAction, rate: () -> Void) {
        switch action {
        case .favorite:
            if model.isLoggedIn { model.quickFavorite() } else { signIn() }
        case .favoriteIn(let folder):
            model.favorite(category: folder)
        case .unfavorite:
            model.unfavorite()
        case .read:
            model.read()
        case .comments:
            model.destination = .comments(scrollTo: nil)
        case .rate:
            if model.isLoggedIn { rate() } else { signIn() }
        default:
            break
        }
    }

    // MARK: Actions

    /// Rate from the top bar or the dock: the popover belongs to the Rating fact, so the table
    /// comes into view first.
    private func rate(_ proxy: ScrollViewProxy) {
        guard model.detail != nil, !model.showsRatingControl else { return }
        proxy.scrollTo(Self.factsID, anchor: .top)
        model.toggleRatingControl()
    }

    private func search(_ keyword: String) {
        searchCount += 1
        stack?.push(.search(keyword: keyword))
    }

    private func searchUploader(_ uploader: String) {
        search(DetailSearchKeyword.uploader(uploader))
    }

    private func copy(_ text: String) {
        clipboard.copyText(text)
        copyCount += 1
        hud = .copiedToClipboard
    }

    private func signIn() {
        appRouter?.presentSettings([.settings(.account), .settings(.login)])
    }
}

/// Under the header when the page shown is the stored one because it could not be fetched:
/// "Offline · showing the saved page", or what went wrong, with Retry.
private struct LedgerGalleryBanner: View {
    let error: AppError
    let retry: () -> Void

    @Environment(\.look) private var look

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: error == .networkingFailed ? "wifi.exclamationmark" : "exclamationmark.triangle")
                .foregroundStyle(look.secondaryLabel)
            Text(error == .networkingFailed ? L10n.Localizable.Gallery.offline : error.alertText)
                .font(.footnote)
                .foregroundStyle(look.secondaryLabel)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            if error.isRetryable {
                Button(L10n.Localizable.ErrorView.Button.retry, action: retry)
                    .font(.footnote.weight(.semibold))
                    .buttonStyle(.plain)
                    .foregroundStyle(.tint)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(look.surface, in: .rect(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
