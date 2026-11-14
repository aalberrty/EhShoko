import EhCore
import EhFeatures
import EhModels
import SwiftUI

/// The `tabs` bar (`Design/designs/README.md` section 5.1, `shelf.md` section 1): the
/// system's tab bar with Home, Watched, Top, Library and the search tab, each a stack of its
/// own, and Continue as the bar's accessory.
///
/// A first working form: task A1 builds the bar's own pieces (the accessory's content and
/// its inline form, minimising, the Library tab) in this folder. What is the shell's stays:
/// one `StackHost` per tab, the bar hidden on gallery routes from each stack's root, the
/// style chosen from the settings alone, and the rule for when the accessory is on
/// (`spikes/S3.md`, `spikes/S5.md`).
struct TabsShell: View {
    let model: AppModel

    /// Where the search tab was entered from, which is the scope its surface starts on.
    @State private var search = TabsBarSearchOrigin()
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        let router = model.router
        TabView(selection: selection) {
            Tab(L10n.Localizable.TabItem.Title.home, systemImage: "house", value: AppTab.home) {
                HomeStackHost(router: router.home)
            }
            Tab(L10n.Localizable.Shell.Tab.watched, systemImage: "eye", value: AppTab.watched) {
                StackHost(router: router.watched) {
                    GalleryListScreen(context: .place(.watched)).tabsAccountButton()
                }
            }
            Tab(L10n.Localizable.Shell.Tab.top, systemImage: "chart.bar", value: AppTab.top) {
                StackHost(router: router.top) {
                    GalleryListScreen(context: .top)
                }
            }
            Tab(L10n.Localizable.Shell.Tab.library, systemImage: "books.vertical", value: AppTab.library) {
                StackHost(router: router.library) {
                    TabsBarLibraryTab().tabsAccountButton()
                }
            }
            Tab(value: AppTab.search, role: .search) {
                StackHost(router: router.search) {
                    SearchSurface(scope: search.scope)
                }
                // The capsule that stands in for the accessory rides above the keyboard, so
                // the search surface never shows it.
                .environment(\.tabsBarKeepsLegacyAccessory, false)
            }
        }
        .modifier(TabsBarStyle(hasLeadingColumn: StartStructure.hasLeadingColumn(settings)))
        .modifier(TabsBarAccessoryHost(router: router, hasLeadingColumn: StartStructure.hasLeadingColumn(settings)))
        .tabBarMinimizesOnScroll()
        .environment(\.tabsBarKeepsLegacyAccessory, true)
        .sensoryFeedback(.impact(flexibility: .soft), trigger: model.tabReselectionFeedback)
    }

    /// Routed through the model so that re-selecting a tab pops or reloads it, with haptics.
    private var selection: Binding<AppTab> {
        Binding(
            get: { model.router.selectedTab },
            set: { tab in
                let current = model.router.selectedTab
                if tab == .search, current != .search {
                    search.scope = TabsBarSearchOrigin.scope(from: current)
                }
                model.selectTab(tab)
            }
        )
    }
}

/// The scope the search surface starts on: the tab the user came from.
nonisolated struct TabsBarSearchOrigin: Equatable, Sendable {
    var scope = SearchScope.everywhere

    static func scope(from tab: AppTab) -> SearchScope {
        switch tab {
        case .library: .favorites
        case .watched: .watched
        case .home, .top, .search: .everywhere
        }
    }
}

/// The tab view's style, from the settings alone: changing it rebuilds every tab, so it
/// never follows the width. With a leading column (Ledger's Index) the bar stays a bar, or
/// there would be two sidebars side by side.
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

/// The accessory and when it is on. Its own modifier, so that a push or a pop in the selected
/// stack runs this body and not the tab view's.
private struct TabsBarAccessoryHost: ViewModifier {
    let router: AppRouter
    let hasLeadingColumn: Bool

    @Environment(ContinueModel.self) private var continueModel
    @Environment(\.horizontalSizeClass) private var sizeClass

    func body(content: Content) -> some View {
        content.tabAccessory(isEnabled: isEnabled) {
            TabsBarAccessory()
        }
    }

    /// On while something is in progress and the selected stack shows the tab bar. Off
    /// beside a side gallery, whose dock it would lift, and while the Index column shows,
    /// which has Continue itself.
    private var isEnabled: Bool {
        guard TabAccessoryKind.usesSystemAccessory, continueModel.first != nil else { return false }
        let stack = router.selectedStack
        let showsLeadingColumn = hasLeadingColumn && sizeClass == .regular && router.selectedTab == .home
        return !stack.hidesBrowseChrome && stack.sideGallery == nil && !showsLeadingColumn
    }
}
