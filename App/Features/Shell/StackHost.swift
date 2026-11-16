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
    /// beside it.
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
            PlaceRootedStack(router: router, columnWidth: { apply(layout.measured(list: $0)) }) {
                GalleryListScreen(context: .place(.frontpage))
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { apply(layout.measured(split: $0)) }
    }

    private func apply(_ change: NavigationSplitViewVisibility?) {
        if let change { visibility = change }
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

    /// The tab bar's accessory is off while the column shows, so the column keeps Continue.
    private func columnChrome(isLeadingColumn: Bool) -> ChromeContext {
        ChromeContext(bar: chrome.bar, continueIsInChrome: false, isLeadingColumn: isLeadingColumn)
    }
}

/// Where the list column of Ledger's split view starts, from the split view's width and the
/// list column's rather than from the column's visibility, which says `.all` both when the
/// Index is beside the list and when it lies over it.
///
/// When the list loses the room beside the Index without a size transition (a side pane
/// opening in portrait), the system lays the Index over the list and keeps the visibility at
/// `.all`, so the list's chrome stays covered until the Index is dismissed. The host hides the
/// Index instead, as the system does itself on a rotation, and shows it again when the split
/// view is wide enough: as wide as the Index has been beside the list in, or wide enough for a
/// list as wide as the Index (where the system has been seen to tile them: a 355 pt list beside
/// the iPad mini's 280 pt Index, never a 248 pt one beside the 13-inch's 330). If the system
/// lays it over the list all the same, it is hidden again. A choice the user makes with the
/// column's button stays as they made it. While a window is resized the two widths pass
/// through values that belong to no layout, so only an inset as wide as the Index counts as
/// the Index beside the list.
nonisolated private struct LeadingColumnLayout: Equatable {
    private var split: CGFloat = 0
    private var list: CGFloat = 0
    /// The Index's content, which is as wide as its column without the margins around it.
    private var column: CGFloat = 0
    /// How far the list starts from the split view's leading edge in the last layout whose two
    /// widths agree.
    private var measuredInset: CGFloat = 0
    private var isMeasured = false
    private var isShown = true
    /// The narrowest split view the Index has been beside the list in.
    private var narrowestBeside = CGFloat.infinity
    /// The split view's width when the host hid the Index for want of room, until it shows it
    /// again or the user changes the column.
    private var hiddenAt: CGFloat?
    /// The host has just shown the Index again, and it is coming in beside the list.
    private var isReturning = false

    /// How far the list column starts from the split view's leading edge: the Index's width
    /// while it is beside the list, zero while it is hidden or over the list.
    var listInset: CGFloat { isShown ? measuredInset : 0 }

    /// The Index is shown but lies over the list.
    var isColumnOverList: Bool { isShown && isMeasured && measuredInset == 0 && !isReturning }

    /// The split view, the list column or the Index was laid out. Each returns the visibility the host
    /// sets, if it changes it.
    mutating func measured(split: CGFloat) -> NavigationSplitViewVisibility? {
        self.split = split
        return settle()
    }

    mutating func measured(list: CGFloat) -> NavigationSplitViewVisibility? {
        self.list = list
        return settle()
    }

    mutating func measured(column: CGFloat) -> NavigationSplitViewVisibility? {
        self.column = column
        return settle()
    }

    mutating func userChose(isShown: Bool) {
        self.isShown = isShown
        hiddenAt = nil
    }

    /// What the system puts around the Index's content: 10 pt for iOS 26's floating sidebar.
    private static let columnMargins: CGFloat = 24

    private mutating func settle() -> NavigationSplitViewVisibility? {
        // The two are measured in separate layouts: a list wider than the split view is one
        // width ahead of the other.
        guard list > 0, split > 0, list <= split + 1 else { return nil }
        let inset = split - list > 1 ? split - list : 0
        let wasBeside = isMeasured && isShown && measuredInset > 0
        let wasReturning = isReturning
        isMeasured = true
        isReturning = false
        measuredInset = inset
        if isShown, inset > 0 {
            if abs(inset - column) <= Self.columnMargins {
                narrowestBeside = min(narrowestBeside, split)
            }
        } else if isShown, wasBeside || wasReturning {
            isShown = false
            hiddenAt = split
            return .detailOnly
        } else if !isShown, inset == 0, column > 0, let hiddenAt, split > hiddenAt,
                  split >= min(narrowestBeside, 2 * (column + Self.columnMargins)) {
            self.hiddenAt = nil
            isShown = true
            isReturning = true
            return .all
        }
        return nil
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
