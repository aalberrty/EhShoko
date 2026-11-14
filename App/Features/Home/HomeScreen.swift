import EhFeatures
import EhModels
import SwiftUI

/// The Home tab root: Popular cards and shortcuts to the lists. The Front Page strip and the
/// Toplists columns went with `HomeModel`'s other sections; their lists are shortcuts until the
/// first-screen designs replace this screen.
struct HomeScreen: View {
    @State private var model = HomeModel()

    @Environment(StackRouter.self) private var stack
    @Environment(AppRouter.self) private var router

    var body: some View {
        content
            .animation(.default, value: model.entries.isEmpty)
            .navigationTitle(L10n.Localizable.HomeView.Title.home)
            .toolbar { reloadItem }
            // The model owns the loads, so pushing a gallery does not cancel them.
            .onAppear { model.loadIfNeeded() }
            // `AppModel.selectTab` plays the re-selection haptic.
            .onChange(of: router.rootReselectionCount(for: .home)) {
                model.reload()
            }
    }

    /// The whole page waits for Popular, as in legacy.
    @ViewBuilder
    private var content: some View {
        if !model.entries.isEmpty {
            HomeSectionsView(model: model, open: open, openList: openList)
        } else if let error = model.loadingState.failed {
            ErrorStateView(error: error, retry: model.reload)
        } else {
            LoadingStateView()
        }
    }

    private var reloadItem: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            if model.loadingState.isLoading {
                ProgressView()
            } else {
                Button(action: model.reload) {
                    Label(L10n.Localizable.ReadingView.ContextMenu.Button.reload, systemImage: "arrow.counterclockwise")
                }
            }
        }
    }

    private func open(_ gallery: Gallery) {
        stack.push(.detail(gallery))
    }

    private func openList(_ kind: GalleryListKind) {
        stack.push(.galleryList(kind))
    }
}

/// The loaded page. Each section reads only the model properties it renders.
private struct HomeSectionsView: View {
    let model: HomeModel
    let open: (Gallery) -> Void
    let openList: (GalleryListKind) -> Void

    /// Written here, read only by the carousel, so a scroll starting or ending re-renders the
    /// carousel and not the whole page.
    @State private var scrolling = PageScrollState()

    var body: some View {
        ScrollView {
            VStack(spacing: Tokens.Spacing.xxLarge) {
                HomeCardCarousel(
                    cards: Array(model.entries.prefix(HomeCardCarousel.maximumCards)),
                    pageScrolling: scrolling, open: open
                )
                SubSection(title: L10n.Localizable.HomeView.Section.Title.other, showsAll: false) {
                    HomeShortcuts(open: openList)
                }
            }
            .padding(.vertical, Tokens.Spacing.small)
        }
        .scrollIndicators(.hidden)
        .onScrollPhaseChange { _, phase in scrolling.isScrolling = phase.isScrolling }
    }
}

#Preview {
    NavigationStack {
        HomeScreen()
    }
    .environment(StackRouter())
    .environment(AppRouter())
}
