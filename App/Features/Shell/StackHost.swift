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
    /// Something is drawn over the stack: the command bar's search surface.
    var isCovered = false
    @ViewBuilder var root: Root
    @ViewBuilder var bar: (BarControl?, @escaping (BarAction) -> Void) -> Bar

    var body: some View {
        BottomChrome(
            router: router, hasBar: hasBar, isCovered: isCovered,
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
    /// Something is drawn over the stack: the command bar's search surface.
    var isCovered = false
    @ViewBuilder var bar: (BarControl?, @escaping (BarAction) -> Void) -> Bar

    @Environment(SettingsStore.self) private var settings
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        if StartStructure.hasLeadingColumn(settings), sizeClass == .regular {
            LeadingColumnHost(router: router, hasBar: hasBar, isCovered: isCovered, bar: bar)
        } else {
            StackHost(
                router: router, hasBar: hasBar, isCovered: isCovered,
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
    let isCovered: Bool
    let bar: (BarControl?, @escaping (BarAction) -> Void) -> Bar

    @State private var visibility = NavigationSplitViewVisibility.all
    /// The split view's width and its list column's, which says where the list starts.
    @State private var widths = ColumnWidths()
    @Environment(\.chrome) private var chrome

    var body: some View {
        BottomChrome(
            router: router, hasBar: hasBar,
            leadingInset: widths.columnInset,
            isCovered: isCovered || indexIsOverList,
            content: { columns },
            bar: bar
        )
        .opensGalleries(on: router)
        .environment(\.chrome, columnChrome(isLeadingColumn: false))
    }

    /// The Index is shown but the list did not make room for it: it lies over the list (in
    /// portrait beside a side pane, and on iOS 18 in portrait), and the list's chrome would
    /// show through the column's glass. The split view keeps reporting `.all` while it is
    /// collapsed, which this host never is: it exists only on regular width.
    private var indexIsOverList: Bool {
        (visibility == .all || visibility == .doubleColumn) && widths.columnInset == 0
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
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { widths.list = $0 }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { widths.split = $0 }
    }

    /// The tab bar's accessory is off while the column shows, so the column keeps Continue.
    private func columnChrome(isLeadingColumn: Bool) -> ChromeContext {
        ChromeContext(bar: chrome.bar, continueIsInChrome: false, isLeadingColumn: isLeadingColumn)
    }
}

/// Where the list column of Ledger's split view starts, taken from the widths rather than from
/// the column's visibility, which says `.all` both when the Index is beside the list and when
/// it lies over it.
nonisolated private struct ColumnWidths: Equatable {
    var split: CGFloat = 0
    var list: CGFloat = 0

    /// How far the list column starts from the split view's leading edge: the Index column's
    /// width while it is beside the list, zero while it is hidden or over the list.
    var columnInset: CGFloat {
        guard list > 0 else { return 0 }
        let inset = split - list
        // The two are measured in separate layouts and may differ by a fraction.
        return inset > 1 ? inset : 0
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
