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
        } detail: {
            PlaceRootedStack(router: router) {
                GalleryListScreen(context: .place(.frontpage))
            }
            // Where the list starts and how wide the split view is, in one measurement, so
            // the two always come from the same layout. The list column ends where the split
            // view does.
            .onGeometryChange(for: ListColumnFrame.self) { proxy in
                let frame = proxy.frame(in: .named(LeadingColumnLayout.space))
                return ListColumnFrame(minX: frame.minX, splitWidth: frame.maxX)
            } action: { frame in
                if let change = layout.measured(frame) { visibility = change }
            }
        }
        .coordinateSpace(.named(LeadingColumnLayout.space))
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

nonisolated private struct ListColumnFrame: Equatable {
    let minX: CGFloat
    let splitWidth: CGFloat
}

/// Where the list column of Ledger's split view starts, from its frame rather than from the
/// column's visibility, which says `.all` both when the Index is beside the list and when it
/// lies over it.
///
/// When the list loses the room beside the Index without a size transition (a side pane
/// opening in portrait), the system lays the Index over the list and keeps the visibility at
/// `.all`, so the list's chrome stays covered until the Index is dismissed. The host hides the
/// Index instead, as the system does itself on a rotation, and shows it again when the split
/// view is wide enough: as wide as the Index has been beside the list in, or wide enough for a
/// list as wide as the Index (where the system has been seen to tile them: a 355 pt list beside
/// the iPad mini's 280 pt Index, never a 248 pt one beside the 13-inch's 330). If the system
/// lays it over the list all the same, it is hidden again. A choice the user makes with the
/// column's button stays as they made it.
nonisolated private struct LeadingColumnLayout: Equatable {
    /// The split view's coordinate space, which the list column is measured in.
    static let space = "leadingColumnSplit"

    /// How far the list column starts from the split view's leading edge: the Index's width
    /// while it is beside the list, zero while it is hidden or over the list.
    private(set) var listInset: CGFloat = 0
    private var isShown = true
    private var isMeasured = false
    /// The narrowest split view the Index has been beside the list in, and its width there.
    private var narrowestBeside = CGFloat.infinity
    private var columnWidth: CGFloat = 0
    /// The split view's width when the host hid the Index for want of room, until it shows it
    /// again or the user changes the column.
    private var hiddenAt: CGFloat?
    /// The host has just shown the Index again, and it is coming in beside the list.
    private var isReturning = false

    /// The Index is shown but lies over the list.
    var isColumnOverList: Bool { isShown && isMeasured && listInset == 0 && !isReturning }

    /// The list column was laid out. Returns the visibility the host sets, if it changes it.
    mutating func measured(_ frame: ListColumnFrame) -> NavigationSplitViewVisibility? {
        let wasBeside = isMeasured && listInset > 0
        let wasReturning = isReturning
        isMeasured = true
        isReturning = false
        listInset = frame.minX > 1 ? frame.minX : 0
        let width = frame.splitWidth
        if listInset > 0 {
            narrowestBeside = min(narrowestBeside, width)
            columnWidth = listInset
        } else if isShown, wasBeside || wasReturning {
            isShown = false
            hiddenAt = width
            return .detailOnly
        } else if let hiddenAt, !isShown, width > hiddenAt, width >= min(narrowestBeside, 2 * columnWidth) {
            self.hiddenAt = nil
            isShown = true
            isReturning = true
            return .all
        }
        return nil
    }

    mutating func userChose(isShown: Bool) {
        self.isShown = isShown
        hiddenAt = nil
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
