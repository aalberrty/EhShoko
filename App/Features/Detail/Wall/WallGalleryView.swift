import Dependencies
import EhCore
import EhFeatures
import EhModels
import SwiftUI

// Wall's gallery page and the screens opened from it: a card. The cover stands on a backdrop
// in its own colours and a panel with everything else scrolls up over both.
//
// `GalleryPage` and `GalleryChildScreen` call the three types of this file. The page declares
// its bottom actions with `.dock(_:perform:)` and presents nothing itself but the rating's
// popover: the load, the pushed children, the sheets and the reader are `GalleryPage`'s,
// around every design.

/// The page: pushed, in the side pane (`chrome.isSidePane`) or in the gallery sheet
/// (`chrome.isSheet`).
struct WallGalleryView: View {
    let model: GalleryDetailModel

    @Environment(\.chrome) private var chrome
    @Environment(\.look) private var look
    @Environment(\.dismiss) private var dismiss
    @Environment(AppRouter.self) private var appRouter: AppRouter?
    @Environment(StackRouter.self) private var stack: StackRouter?
    @Environment(UserStore.self) private var userStore

    /// The height of the bars over the page, which the panel's resting place allows for. It
    /// starts at a phone's and is measured in the first layout.
    @State private var topInset: CGFloat = 103
    @State private var hud: HUDConfiguration?

    @Dependency(\.clipboardClient) private var clipboard

    var body: some View {
        let metrics = WallGalleryMetrics(chrome: chrome)
        ScrollView {
            VStack(spacing: 0) {
                // The cover and the backdrop show through here until the panel is pulled up.
                Color.clear
                    .frame(height: max(metrics.panelTop - topInset, 0))
                WallGalleryPanel(model: model, metrics: metrics, copy: copy, signIn: signIn)
            }
        }
        .scrollIndicators(.hidden)
        .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.top } action: { topInset = $0 }
        .background(alignment: .top) {
            WallGalleryBackdrop(coverURL: model.gallery.coverURL ?? model.detail?.coverURL, metrics: metrics)
        }
        .background(metrics.ground(in: look))
        .navigationBarTitleDisplayMode(.inline)
        // In the pane the shell's Close stands in this place, and a page pushed there keeps
        // the stack's Back.
        .navigationBarBackButtonHidden(!chrome.isSidePane)
        .toolbar { toolbar }
        // Declared from the first frame, from what the list knew, so that the command bar
        // turns into the dock instead of leaving before it arrives.
        .dock(WallGalleryDock.content(for: model, folderName: userStore.favoriteFolderName)) {
            perform($0)
        }
        .hud($hud)
        .onChange(of: model.favoriteReport) { _, report in
            guard let report else { return }
            hud = .symbol(
                "heart.fill", title: L10n.Localizable.List.Favorited.hud(userStore.favoriteFolderName(report.folder))
            )
            FavoriteTip.record(report)
        }
    }

    /// Close and Share, which the system draws: glass circles over the backdrop on iOS 26.
    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if !chrome.isSidePane {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.down")
                }
            }
        }
        if let galleryURL = model.gallery.galleryURL {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: galleryURL) {
                    Label(L10n.Localizable.DetailView.ToolbarItem.Button.share, systemImage: "square.and.arrow.up")
                }
            }
        }
    }

    private func perform(_ action: DockAction) {
        switch action {
        case .favorite:
            if model.isLoggedIn { model.quickFavorite() } else { signIn() }
        case .favoriteIn(let folder):
            if model.isLoggedIn { model.favorite(category: folder) } else { signIn() }
        case .unfavorite:
            if model.isLoggedIn { model.unfavorite() } else { signIn() }
        case .read:
            model.read()
        case .comments:
            model.destination = .comments(scrollTo: nil)
        case .galleryInfos:
            model.destination = .galleryInfos
        case .similarGalleries:
            if let keyword = model.similarGalleryKeyword {
                stack?.push(.search(keyword: keyword))
            }
        case .archive:
            if model.isLoggedIn { model.showArchives() } else { signIn() }
        case .torrents:
            model.showTorrents()
        case .rate, .writeComment, .share, .other:
            break
        }
    }

    private func copy(_ text: String) {
        clipboard.copyText(text)
        hud = .copiedToClipboard
    }

    /// What a dimmed action does for someone without an account.
    private func signIn() {
        appRouter?.presentSettings([.settings(.login)])
    }
}

/// A pushed child screen: comments, all previews, gallery infos.
struct WallGalleryChildView: View {
    let route: DetailChildRoute

    var body: some View {
        let model = route.parent
        switch route.destination {
        case .comments(let commentID):
            WallCommentsView(detail: model, scrollTo: commentID)
        case .previews:
            WallPreviewsView(detail: model)
        case .galleryInfos:
            if let detail = model.detail {
                WallGalleryInfosView(gallery: model.gallery, detail: detail)
            }
        case .archives, .torrents, .postComment, .tagDetail, .reader:
            EmptyView()
        }
    }
}

/// The content of a sheet: tag detail, archives, torrents, the comment composer. Each opens
/// at the medium detent, where the sheet is glass on iOS 26, so a list inside draws no
/// ground of its own.
struct WallGallerySheet: View {
    let destination: DetailDestination
    let model: GalleryDetailModel

    var body: some View {
        switch destination {
        case .archives(let archiveURL):
            WallArchivesSheet(gallery: model.gallery, archiveURL: archiveURL)
        case .torrents:
            TorrentsSheet(gid: model.gallery.gid, token: model.gallery.token)
                .scrollContentBackground(.hidden)
        case .postComment:
            PostCommentSheet(composer: .new) { text in model.postComment(text) }
        case .tagDetail(let detail):
            TagDetailSheet(detail: detail)
        case .comments, .previews, .galleryInfos, .reader:
            EmptyView()
        }
    }
}

/// The card's measures (`wall.md` section 4): a phone's, and the 372 pt side pane's, where
/// the backdrop is shorter, the cover smaller and the panel lies on the look's surface.
nonisolated struct WallGalleryMetrics: Equatable, Sendable {
    let isPane: Bool
    /// From the top of the screen, bars included.
    let backdropHeight: CGFloat
    let coverSize: CGSize
    let coverTop: CGFloat
    /// Where the panel rests, from the top of the screen.
    let panelTop: CGFloat
    let panelCornerRadius: CGFloat
    let panelPadding: CGFloat
    /// How many tags show before "+47".
    let tagLimit: Int

    init(chrome: ChromeContext) {
        isPane = chrome.isSidePane
        if chrome.isSidePane {
            // The pane was drawn without the status bar that stands over it: 24 pt more.
            backdropHeight = 324
            coverSize = CGSize(width: 140, height: 200)
            coverTop = 50
            panelTop = 262
            panelCornerRadius = 26
            panelPadding = 18
            tagLimit = 8
        } else {
            // A sheet has no status bar over it, so everything stands that much higher.
            let lift: CGFloat = chrome.isSheet ? 30 : 0
            backdropHeight = 400 - lift
            coverSize = CGSize(width: 160, height: 229)
            coverTop = 70 - lift
            panelTop = 318 - lift
            panelCornerRadius = 32
            panelPadding = 20
            tagLimit = 11
        }
    }

    /// What the panel lies on, which is also the page's ground under the backdrop.
    func ground(in look: Look) -> Color {
        isPane ? look.surface : look.background
    }

    /// Chips and round actions: one step off the ground.
    func fill(in look: Look) -> Color {
        isPane ? look.fill3 : look.surface
    }
}
