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
    /// Where the list column starts, and the column's visibility when the list loses the room
    /// beside it (`LeadingColumnLayout`, in the package with its tests).
    @State private var layout = LeadingColumnLayout()
    @Environment(\.chrome) private var chrome

    var body: some View {
        BottomChrome(
            router: router, hasBar: hasBar,
            leadingInset: layout.listInset,
            // The column lies over the list, and the list's chrome would show through its glass.
            isCovered: isCovered || layout.isColumnOverList,
            content: { columns },
            bar: bar
        )
        .opensGalleries(on: router)
        .environment(\.chrome, columnChrome(isLeadingColumn: false))
        .onChange(of: visibility == .detailOnly, initial: true) { _, isHidden in
            router.isLeadingColumnHidden = isHidden
        }
        .onDisappear { router.isLeadingColumnHidden = false }
    }

    private var columns: some View {
        NavigationSplitView(columnVisibility: userVisibility) {
            StartScreen()
                .tabsAccountButton()
                .environment(\.chrome, columnChrome(isLeadingColumn: true))
                .environment(router)
                // The column is not a screen of the stack: the chrome is inset past it, and
                // what it declares must not be taken for the root's entry.
                .environment(\.chromeReserve, 0)
                .transformPreference(ChromeKey.self) { $0 = [] }
                .navigationSplitViewColumnWidth(StartStructure.leadingColumnWidth)
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { apply(layout.measured(column: $0)) }
        } detail: {
            // Widths, not positions: the system moves a column without a new layout of what is
            // in it, but a column that changes width lays out its top screen again.
            PlaceRootedStack(
                router: router,
                rootBesideSidebarButton: chrome.bar == .tabs && visibility == .detailOnly,
                columnWidth: { apply(layout.measured(list: $0)) }
            ) {
                GalleryListScreen(context: .place(.frontpage))
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { apply(layout.measured(split: $0)) }
        // Before the pane takes its room: hidden in the update that opens the pane, the Index
        // is never laid over the list for a layout.
        .onSidePaneWidthChange { apply(layout.sidePane(width: $0)) }
    }

    private func apply(_ change: LeadingColumnVisibility?) {
        switch change {
        case .shown: visibility = .all
        case .hidden: visibility = .detailOnly
        case nil: break
        }
    }

    /// The column's visibility, as the user changes it with the sidebar button or by
    /// dismissing the column laid over the list.
    private var userVisibility: Binding<NavigationSplitViewVisibility> {
        Binding(
            get: { visibility },
            set: { new in
                guard new != visibility else { return }
                visibility = new
                layout.userChose(isShown: new == .all || new == .doubleColumn)
            }
        )
    }

    /// The column keeps Continue while it shows; while it is hidden, the tab bar's Continue is
    /// on for the list beside it, as for any other first screen.
    private func columnChrome(isLeadingColumn: Bool) -> ChromeContext {
        let continueIsInChrome = !isLeadingColumn && chrome.bar == .tabs && visibility == .detailOnly
        return ChromeContext(bar: chrome.bar, continueIsInChrome: continueIsInChrome, isLeadingColumn: isLeadingColumn)
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
