import Dependencies
import EhCore
import EhFeatures
import EhModels
import SwiftUI

// Wall's gallery page and the screens opened from it (`Design/designs/wall.md` section 4).
//
// `GalleryPage` and `GalleryChildScreen` (Shell/Parts) call the three entry types:
// `WallGalleryView`, `WallGalleryChildView` and `WallGallerySheet`. The load, the pushed
// children, the sheets and the reader are `GalleryPage`'s, around every design: this page
// draws the model, declares its dock and sets `model.destination`; it presents nothing itself.

/// The page, a card: the cover on a backdrop of its own colours, and a panel that scrolls up
/// over it. Pushed (the zoom from the list lands on the cover), in the gallery sheet, or in
/// the side pane (`chrome.isSidePane`), where it is the smaller card on the look's surface.
///
/// Close and Share are toolbar items, so the system draws them: Close, a chevron down, stands
/// where Back would be, because the card is put away downwards (the zoom's own pull). In the
/// side pane the shell's Close is there instead.
struct WallGalleryView: View {
    let model: GalleryDetailModel

    @Environment(AppRouter.self) private var appRouter: AppRouter?
    @Environment(StackRouter.self) private var stack: StackRouter?
    @Environment(UserStore.self) private var userStore
    @Environment(\.chrome) private var chrome
    @Environment(\.look) private var look
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Dependency(\.clipboardClient) private var clipboard

    /// The cover's colours, taken once and kept while the page exists.
    @State private var palette: CoverPalette?
    /// The panel has scrolled over the whole cover. It changes when the panel's top passes the
    /// cover's, not while the page scrolls.
    @State private var coverIsCovered = false
    @State private var hud: HUDConfiguration?
    @State private var asksToSignIn = false
    @State private var searchCount = 0
    @State private var copyCount = 0

    var body: some View {
        let metrics = WallGalleryMetrics(isPane: chrome.isSidePane, isShort: verticalSizeClass == .compact)
        let coverURL = model.gallery.coverURL ?? model.detail?.coverURL
        ZStack(alignment: .top) {
            WallGalleryBackdrop(palette: palette, height: metrics.backdropHeight, ground: metrics.ground(look))
                .equatable()
            // Inside the safe area, so its top is the top bar's bottom edge: the cover stands
            // beside the bar's buttons.
            WallGalleryCover(url: coverURL, size: metrics.coverSize)
                .offset(y: -metrics.coverLift)
                // Under the top bar iOS 26 fades what scrolls there, the panel with it, and
                // the cover behind would show through the panel that covers it.
                .opacity(coverIsCovered ? 0 : 1)
            ScrollView {
                VStack(spacing: 0) {
                    // Clear, so the cover shows until the panel has scrolled over it.
                    Color.clear
                        .frame(height: metrics.panelInset)
                        .accessibilityHidden(true)
                    WallGalleryPanel(model: model, metrics: metrics, actions: actions)
                }
            }
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top >= metrics.panelInset + metrics.coverLift
            } action: { _, isCovered in
                withAnimation(.easeOut(duration: 0.15)) { coverIsCovered = isCovered }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .modifier(WallGalleryClose(isShown: showsClose))
        .toolbar { toolbar }
        .wallGalleryDock(model, signIn: signIn, search: search)
        .hud($hud)
        .task(id: coverURL) {
            // Once: the task runs again whenever the page comes back from a child screen.
            guard palette == nil, let coverURL else { return }
            palette = await WallCoverPalette.load(coverURL)
        }
        .onChange(of: model.favoriteReport) { _, report in
            guard let report else { return }
            hud = .symbol("heart.fill", title: L10n.Localizable.List.Favorited.hud(userStore.favoriteFolderName(report.folder)))
            FavoriteTip.record(report)
        }
        .alert(L10n.Localizable.ErrorView.Headline.loginRequired, isPresented: $asksToSignIn) {
            Button(L10n.Localizable.NotLoginView.Button.login) {
                appRouter?.presentSettings([.settings(.account), .settings(.login)])
            }
            AlertCancelButton(title: L10n.Localizable.JumpPageView.Button.cancel)
        } message: {
            Text(L10n.Localizable.List.Signin.note)
        }
        .sensoryFeedback(.success, trigger: copyCount)
        .sensoryFeedback(.impact(flexibility: .soft), trigger: searchCount)
    }

    // MARK: Top bar

    /// The card's own Close: wherever nothing else closes it. The side pane's root has the
    /// shell's Close, and a page pushed inside the pane keeps the system's Back.
    private var showsClose: Bool {
        !chrome.isSidePane
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if let url = model.gallery.galleryURL {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: url) {
                    Label(L10n.Localizable.DetailView.ToolbarItem.Button.share, systemImage: "square.and.arrow.up")
                }
            }
        }
    }

    // MARK: Actions

    private var actions: WallGalleryPanelActions {
        WallGalleryPanelActions(signIn: signIn, search: search, copy: copy)
    }

    private func signIn() {
        asksToSignIn = true
    }

    private func search(_ keyword: String) {
        searchCount += 1
        stack?.push(.search(keyword: keyword))
    }

    private func copy(_ text: String) {
        clipboard.copyText(text)
        copyCount += 1
        hud = .copiedToClipboard
    }
}

/// What the panel's parts ask the page to do: the page owns the sign-in prompt, the stack and
/// the HUD, which would scroll away inside the panel.
struct WallGalleryPanelActions {
    let signIn: () -> Void
    let search: (String) -> Void
    let copy: (String) -> Void
}

/// The card's Close, a chevron down where Back would be. It puts the card away: back to the
/// list it was opened from, or, as the root of a sheet, the sheet. A modifier of its own, so
/// that only this follows the presentation's state.
private struct WallGalleryClose: ViewModifier {
    let isShown: Bool

    @Environment(\.dismiss) private var dismiss

    func body(content: Content) -> some View {
        content
            .navigationBarBackButtonHidden(isShown)
            .toolbar {
                if isShown {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "chevron.down")
                        }
                    }
                }
            }
    }
}
