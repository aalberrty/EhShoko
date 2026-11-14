import EhCore
import EhFeatures
import EhModels
import SwiftUI

/// A browse stack with what goes around it, in the order the spikes found: the stack, the
/// bottom chrome's host around it, the side pane around the host. `TabsShell` puts one in
/// every tab; `CommandShell` has one, with the command bar.
struct StackHost<Root: View, Bar: View>: View {
    let router: StackRouter
    let hasBar: Bool
    @ViewBuilder var root: Root
    @ViewBuilder var bar: (BarControl?, @escaping (BarAction) -> Void) -> Bar

    var body: some View {
        BottomChrome(
            router: router, hasBar: hasBar,
            content: { RoutedStack(router: router) { root } },
            bar: bar
        )
        .opensGalleries(on: router)
    }
}

extension StackHost where Bar == EmptyView {
    /// A stack with no bar of its own: a tab's.
    init(router: StackRouter, @ViewBuilder root: () -> Root) {
        self.init(router: router, hasBar: false, root: root) { _, _ in EmptyView() }
    }
}

/// The `home` stack, whose root is the first screen: under `tabs` the Home tab, under
/// `command` the only stack.
///
/// The first screen decides whether there is a leading column (`README.md` section 5.8,
/// rule 2). Ledger's Index on regular width is the system sidebar of a split view, and then
/// the chrome's host and the side pane go around the whole split view (`spikes/S5.md`).
/// Below regular width the Index is the stack's root, as on a phone. The switch follows the
/// size class, never the width, which changes continuously while a window is dragged.
struct HomeStackHost<Bar: View>: View {
    let router: StackRouter
    let hasBar: Bool
    @ViewBuilder var bar: (BarControl?, @escaping (BarAction) -> Void) -> Bar

    @Environment(SettingsStore.self) private var settings
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        if StartStructure.hasLeadingColumn(settings), sizeClass == .regular {
            LeadingColumnHost(router: router, hasBar: hasBar, bar: bar)
        } else {
            StackHost(
                router: router, hasBar: hasBar,
                root: { StartScreen().tabsAccountButton() },
                bar: bar
            )
        }
    }
}

extension HomeStackHost where Bar == EmptyView {
    init(router: StackRouter) {
        self.init(router: router, hasBar: false) { _, _ in EmptyView() }
    }
}

/// The first screen as the sidebar column of a split view, the list of the current place
/// beside it, and the gallery's side pane beside that: Ledger's three columns.
private struct LeadingColumnHost<Bar: View>: View {
    let router: StackRouter
    let hasBar: Bool
    let bar: (BarControl?, @escaping (BarAction) -> Void) -> Bar

    @State private var visibility = NavigationSplitViewVisibility.all
    @Environment(\.chrome) private var chrome

    /// The split view keeps reporting `.all` while it is collapsed; this host exists only on
    /// regular width, where the column is beside the list whenever it is visible.
    private var columnIsBeside: Bool {
        visibility == .all || visibility == .doubleColumn
    }

    var body: some View {
        BottomChrome(
            router: router, hasBar: hasBar,
            leadingInset: columnIsBeside ? StartStructure.leadingColumnWidth : 0,
            content: { columns },
            bar: bar
        )
        .opensGalleries(on: router)
        .environment(\.chrome, columnChrome(isLeadingColumn: false))
    }

    private var columns: some View {
        NavigationSplitView(columnVisibility: $visibility) {
            StartScreen()
                .tabsAccountButton()
                .environment(\.chrome, columnChrome(isLeadingColumn: true))
                .environment(router)
                // The column is not a screen of the stack: the chrome is inset past it, and
                // what it declares must not be taken for the root's entry.
                .environment(\.chromeReserve, 0)
                .transformPreference(ChromeKey.self) { $0 = [] }
                .navigationSplitViewColumnWidth(StartStructure.leadingColumnWidth)
        } detail: {
            PlaceRootedStack(router: router) {
                GalleryListScreen(context: .place(.frontpage))
            }
        }
    }

    /// The tab bar's accessory is off while the column shows, so the column keeps Continue.
    private func columnChrome(isLeadingColumn: Bool) -> ChromeContext {
        ChromeContext(bar: chrome.bar, continueIsInChrome: false, isLeadingColumn: isLeadingColumn)
    }
}

// MARK: The account button

extension View {
    /// The entry to Settings on a root screen under `tabs`: Home, Watched and Library. The
    /// shell adds it around whatever part draws the root, so it is there for every design.
    /// Under `command` it adds nothing: Settings is in the place menu.
    func tabsAccountButton() -> some View {
        modifier(AccountButtonItem(bar: .tabs))
    }

    /// For a first screen that keeps an account button of its own under `command`: Shelf's
    /// Home and Ledger's Index. Under `tabs` it adds nothing: the shell has added one.
    func startAccountButton() -> some View {
        modifier(AccountButtonItem(bar: .command))
    }
}

private struct AccountButtonItem: ViewModifier {
    /// The bar under which this adds the button.
    let bar: BarStyle

    @Environment(\.chrome) private var chrome
    @Environment(AppRouter.self) private var appRouter

    func body(content: Content) -> some View {
        if chrome.bar == bar {
            content.toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.Localizable.Shell.Account.button, systemImage: "person.crop.circle") {
                        appRouter.presentSettings()
                    }
                }
            }
        } else {
            content
        }
    }
}
