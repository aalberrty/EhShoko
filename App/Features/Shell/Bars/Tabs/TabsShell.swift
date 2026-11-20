import EhCore
import EhFeatures
import EhModels
import SwiftUI

/// The `tabs` bar (`Design/designs/README.md` section 5.1, `shelf.md` section 1): the
/// system's tab bar with Home, Watched, Top, Library and the search tab, each a stack of its
/// own, and Continue as the bar's accessory.
///
/// The bar itself, its glass and its minimising are the system's. What this folder adds: the
/// accessory's content and when it is on (`TabsBarAccessoryHost`), the capsule that stands
/// in for it on the older systems (`TabsBarLegacyAccessory`), the Library tab's switch
/// (`TabsBarLibraryTab`), where the search tab's scope comes from, and what the bar does for
/// each tab's stack (`TabsBarStack`): hiding itself on gallery routes and counting the
/// re-selections for the list at the root. What the spikes found and must stay
/// (`spikes/S3.md`, `spikes/S5.md`): one `StackHost` per tab; the bar hidden from the path,
/// never by the destination; the style chosen from the settings alone; the accessory and the
/// style never added, removed or changed with an `if`, which rebuilds every tab.
struct TabsShell: View {
    let model: AppModel

    /// Where the search tab was entered from, which is the scope its surface starts on.
    @State private var search = TabsBarSearchOrigin()
    /// The Library tab's Favourites / History switch, which another tab can set.
    @State private var library = TabsBarLibrarySwitch()
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        let router = model.router
        let hasLeadingColumn = StartStructure.hasLeadingColumn(settings)
        TabView(selection: selection) {
            Tab(L10n.Localizable.TabItem.Title.home, systemImage: "house", value: AppTab.home) {
                HomeStackHost(router: router.home)
                    .modifier(TabsBarStack(tab: .home))
            }
            Tab(L10n.Localizable.Shell.Tab.watched, systemImage: "eye", value: AppTab.watched) {
                StackHost(router: router.watched) {
                    GalleryListScreen(context: .place(.watched)).tabsAccountButton()
                }
                .modifier(TabsBarStack(tab: .watched))
            }
            Tab(L10n.Localizable.Shell.Tab.top, systemImage: "chart.bar", value: AppTab.top) {
                // No account button: the list's page menu is in that position.
                StackHost(router: router.top) {
                    GalleryListScreen(context: .top)
                }
                .modifier(TabsBarStack(tab: .top))
            }
            Tab(L10n.Localizable.Shell.Tab.library, systemImage: "books.vertical", value: AppTab.library) {
                StackHost(router: router.library) {
                    TabsBarLibraryTab(library: library).tabsAccountButton()
                }
                .modifier(TabsBarStack(tab: .library))
            }
            Tab(value: AppTab.search, role: .search) {
                StackHost(router: router.search) {
                    SearchSurface(scope: search.scope)
                }
                .modifier(TabsBarStack(tab: .search))
                // Continue is not on the search surface, only on the results pushed over it.
                .environment(\.tabsBarHoldsSearchSurface, true)
            }
        }
        .modifier(TabsBarStyle(hasLeadingColumn: hasLeadingColumn))
        .modifier(TabsBarAccessoryHost(router: router, hasLeadingColumn: hasLeadingColumn))
        .tabBarMinimizesOnScroll()
        .environment(\.tabsBarKeepsLegacyAccessory, true)
        .environment(\.showLibraryHistory, TabsBarHistoryOpener(router: router, library: library))
        .sensoryFeedback(.impact(flexibility: .soft), trigger: model.tabReselectionFeedback)
    }

    /// Routed through the model so that re-selecting a tab pops or reloads it, with haptics.
    /// A tap on the minimised bar only expands it and does not come through here, so getting
    /// the bar back never pops a stack (`spikes/S3.md`, question 1).
    private var selection: Binding<AppTab> {
        Binding(
            get: { model.router.selectedTab },
            set: { tab in
                let current = model.router.selectedTab
                if tab == .search, current != .search {
                    search.scope = TabsBarSearchOrigin.scope(from: current, library: library.segment)
                }
                model.selectTab(tab)
            }
        )
    }
}

/// The scope the search surface starts on: where the user came from.
nonisolated struct TabsBarSearchOrigin: Equatable, Sendable {
    var scope = SearchScope.everywhere

    /// Watched gives Watched and the Library's Favourites give Favourites. History, like
    /// every other list, has no scope of its own and gives Everywhere, as the History place
    /// does under the command bar.
    static func scope(from tab: AppTab, library: TabsBarLibrarySegment) -> SearchScope {
        switch tab {
        case .library: library == .favorites ? .favorites : .everywhere
        case .watched: .watched
        case .home, .top, .search: .everywhere
        }
    }
}

/// The tab view's style, from the settings alone: changing it rebuilds every tab, so it
/// never follows the width. On an iPad both styles float the bar at the top; the adaptable
/// one can turn into the system's sidebar. With a leading column (Ledger's Index) the bar
/// stays a bar, or there would be two sidebars side by side (`spikes/S5.md` section 3).
private struct TabsBarStyle: ViewModifier {
    let hasLeadingColumn: Bool

    func body(content: Content) -> some View {
        if hasLeadingColumn {
            content.tabViewStyle(.tabBarOnly)
        } else {
            content.tabViewStyle(.sidebarAdaptable)
        }
    }
}
