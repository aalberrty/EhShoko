import Dependencies
import EhCore
import EhFeatures
import EhModels
import SwiftUI

/// The tab bar and the navigation stack of each tab, the gallery sheet for links opened from
/// outside the app and the New Dawn greeting.
///
/// Feature screens never reference each other. A feature shows another feature's screen by
/// pushing a `Route` onto the `StackRouter` in its environment; `RouteDestination` maps the
/// route to the owning feature's entry view. Settings is an ordinary tab on iPad too.
///
/// Until the new shell replaces this view, its Favorites tab is the router's `library` stack
/// and its Settings tab shows the router's Settings stack: the tab is selected exactly while
/// `AppRouter` says Settings is presented, so `presentSettings` still opens it.
struct MainTabView: View {
    let model: AppModel

    /// Bumped when re-selecting the Settings tab pops it, for the legacy soft haptic.
    @State private var settingsReselectionFeedback = 0

    // Shared services, created by the launch off the main actor. They are injected into the
    // environment so views read the individual properties they render; models reach the same
    // instances through `@Dependency`.
    @Dependency(\.filterStore) private var filterStore
    @Dependency(\.userStore) private var userStore
    @Dependency(\.tagTranslationService) private var tagTranslationService
    @Dependency(\.accountSession) private var accountSession

    var body: some View {
        let router = model.router
        TabView(selection: selectedTab) {
            Tab(L10n.Localizable.TabItem.Title.home, systemImage: "house", value: TabSelection.app(.home)) {
                RoutedStack(router: router.home) { HomeScreen() }
            }
            Tab(
                L10n.Localizable.TabItem.Title.favorites, systemImage: "heart",
                value: TabSelection.app(.library)
            ) {
                RoutedStack(router: router.library) { FavoritesScreen() }
            }
            Tab(value: TabSelection.app(.search), role: .search) {
                RoutedStack(router: router.search) { SearchScreen() }
            }
            Tab(L10n.Localizable.TabItem.Title.setting, systemImage: "gearshape", value: TabSelection.settings) {
                RoutedStack(router: router.settings) { SettingsScreen() }
            }
        }
        .sheet(item: presentedGallery) { gallery in
            RoutedStack(router: router.presented) {
                // The link's target (an image page or a comment) is honoured once.
                GalleryDetailDestination(
                    gallery: gallery, intent: router.takePresentedGalleryTarget(for: gallery.gid).map(DetailIntent.init)
                )
            }
                // The detail screen in this sheet may receive the greeting; only the topmost
                // presenter can show it.
                .newDawnSheet(router: router, isTopmost: true)
        }
        .newDawnSheet(router: router, isTopmost: router.presentedGallery == nil)
        .hud(linkHUD)
        .sensoryFeedback(.impact(flexibility: .soft), trigger: model.tabReselectionFeedback)
        .sensoryFeedback(.impact(flexibility: .soft), trigger: settingsReselectionFeedback)
        .sensoryFeedback(.impact(weight: .light), trigger: router.presentedGallery?.gid) { _, new in new != nil }
        .task(id: model.links.request) { await model.links.handleRequest() }
        .task(id: model.activationRequest) { await model.performActivationWork() }
        .environment(filterStore)
        .environment(userStore)
        .environment(tagTranslationService)
        .environment(accountSession)
    }

    /// Routed through the model so that re-selecting a tab pops or reloads it, with haptics.
    private var selectedTab: Binding<TabSelection> {
        Binding(
            get: { model.router.isSettingsPresented ? .settings : .app(model.router.selectedTab) },
            set: { select($0) }
        )
    }

    private func select(_ selection: TabSelection) {
        let router = model.router
        switch selection {
        case .settings where router.isSettingsPresented:
            // Legacy: re-selecting Settings pops it, with the haptic only when it pops.
            guard !router.settings.isAtRoot else { return }
            router.settings.popToRoot()
            settingsReselectionFeedback += 1
        case .settings:
            router.presentSettings(router.settings.path)
        case .app(let tab) where router.isSettingsPresented:
            // Back from Settings to a tab is a switch, never a re-selection.
            router.dismissSettings()
            if tab != router.selectedTab { model.selectTab(tab) }
        case .app(let tab):
            model.selectTab(tab)
        }
    }

    private var presentedGallery: Binding<Gallery?> {
        Binding(
            get: { model.router.presentedGallery },
            set: { if $0 == nil { model.router.dismissPresentedGallery() } }
        )
    }

    /// Progress of a link being opened; the error HUD clears itself.
    private var linkHUD: Binding<HUDConfiguration?> {
        Binding(
            get: {
                switch model.links.progress {
                case .loading: .loading
                case .failed: .error
                case nil: nil
                }
            },
            set: { if $0 == nil { model.links.progress = nil } }
        )
    }
}

/// The old tab bar's tabs: three of the router's tabs and Settings.
private enum TabSelection: Hashable {
    case app(AppTab)
    case settings
}
