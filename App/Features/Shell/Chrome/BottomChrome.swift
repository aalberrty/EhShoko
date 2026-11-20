import EhFeatures
import SwiftUI
import UIKit

/// The host of the bottom chrome, once around each stack (`Design/designs/spikes/S2.md`
/// section 8): it draws the browse bar or the top screen's dock over the stack, in one glass
/// container, so the bar's three shapes turn into the dock's.
///
/// - Under `command` it has a bar. Under `tabs`, in the side pane and in the gallery sheet it
///   has none and draws only docks, where the tab bar was or at the pane's bottom.
/// - Around Ledger's split view it is inset past the Index column (`leadingInset`), because a
///   split view takes over the stack in its detail column and a host on that stack never
///   sees a pushed screen (`spikes/S5.md`).
/// - While something is drawn over the stack (`isCovered`: the command bar's search surface,
///   Ledger's Index laid over the list; or the side pane laid over it, which the pane says
///   through `\.isUnderSidePane`) the chrome fades out and the screens keep its room.
///
/// It changes what it shows once per navigation: the path and the screens' entries change at
/// different moments, so it decides in one place and only once the top route's entry has
/// arrived. Deciding on either change alone makes a push go bar, nothing, dock in two
/// updates, and then the shapes do not morph.
struct BottomChrome<Content: View, Bar: View>: View {
    private let router: StackRouter
    private let hasBar: Bool
    private let leadingInset: CGFloat
    private let isCovered: Bool
    private let content: Content
    private let bar: (BarControl?, @escaping (BarAction) -> Void) -> Bar

    @State private var entries: [ChromeEntry] = []
    /// The top screen's entry, as last resolved. `nil` until the root has reported.
    @State private var top: ChromeEntry?
    /// Counts the times the chrome came back after showing nothing: each time is a new glass
    /// container with a namespace of its own.
    @State private var appearances = 0
    @State private var isKeyboardUp = false
    @State private var bottomSafeArea: CGFloat = 0
    @Environment(\.isUnderSidePane) private var isUnderSidePane

    /// The bar is 52 pt high and reaches 8 pt below the safe area, so a screen keeps 44 free.
    private static var reserve: CGFloat { ActionDock.height - 8 }
    private static var maximumWidth: CGFloat { 560 }

    /// - Parameters:
    ///   - hasBar: whether `bar` is drawn while the top screen shows browse chrome.
    ///   - isCovered: something is drawn over the stack and its chrome.
    ///   - bar: the browse bar, given the top screen's control for its trailing circle and
    ///     what performs it.
    init(
        router: StackRouter, hasBar: Bool, leadingInset: CGFloat = 0, isCovered: Bool = false,
        @ViewBuilder content: () -> Content,
        @ViewBuilder bar: @escaping (BarControl?, @escaping (BarAction) -> Void) -> Bar
    ) {
        self.router = router
        self.hasBar = hasBar
        self.leadingInset = leadingInset
        self.isCovered = isCovered
        self.content = content()
        self.bar = bar
    }

    /// Something is drawn over the stack, or the side pane lies over it.
    private var isHidden: Bool { isCovered || isUnderSidePane }

    var body: some View {
        content
            // A host further in (a sheet presented from the stack) is not under the pane.
            .environment(\.isUnderSidePane, false)
            .onPreferenceChange(ChromeKey.self) { new in
                entries = new
                resolve(new)
            }
            // Nothing leaks to a host further out: an inspector's entries reach the list's.
            .transformPreference(ChromeKey.self) { $0 = [] }
            .onChange(of: router.path) { resolve(entries) }
            .environment(\.chromeReserve, isKeyboardUp ? 0 : reserve)
            // The reserve changes with what is shown, inside that change's animation, which is
            // for the chrome: the screens are kept out of it where it would hang them. Before
            // the overlay, so the chrome keeps it.
            .bottomBarHeightChangesAtOnce(reserve)
            .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.bottom } action: { bottomSafeArea = $0 }
            .overlay(alignment: .bottom) { chrome }
            // The chrome stays at the bottom under a screen's keyboard, as a tab bar does; the
            // screens inside still avoid the keyboard.
            .ignoresSafeArea(.keyboard, edges: .bottom)
            .task { await keyboardShows() }
            .task { await keyboardHides() }
    }

    // MARK: What is shown

    private var shown: ChromeShown {
        guard let top else { return hasBar ? .bar : .hidden }
        if top.dock != nil { return .dock }
        return hasBar && top.route?.hidesBrowseChrome != true ? .bar : .hidden
    }

    private var reserve: CGFloat {
        hasBar || shown != .hidden ? Self.reserve : 0
    }

    private func resolve(_ entries: [ChromeEntry]) {
        let route = router.path.last
        // The top screen has not reported yet: wait for it.
        guard let entry = entries.last(where: { $0.route == route }), entry != top else { return }
        if top == nil {
            top = entry
        } else {
            let wasHidden = shown == .hidden
            withAnimation(.smooth(duration: 0.4)) {
                top = entry
                if wasHidden, shown != .hidden { appearances += 1 }
            }
        }
    }

    // MARK: The chrome

    private var chrome: some View {
        ZStack {
            // The shapes morph between the bar and a dock inside one container. When nothing
            // takes their place the container goes as a whole and fades: a glass shape that
            // leaves its container with no shape to turn into dissolves, but is cut within a
            // frame when a shape with its slot arrives meanwhile (a dock declared just after its
            // screen). The container that comes next is another one, with its own namespace, so
            // nothing in it is taken for the shapes still fading.
            if shown != .hidden {
                ChromeShapes(shown: shown, top: top, bar: bar)
                    .frame(maxWidth: Self.maximumWidth)
                    .id(appearances)
                    .transition(.opacity)
            }
        }
        .frame(height: ActionDock.height)
        .padding(.horizontal, 12)
        .padding(.leading, leadingInset)
        // The inset follows columns that have already moved; animated, a second change of it
        // while the first runs left the pill's label where the first put it.
        .animation(nil, value: leadingInset)
        // 26 pt above the screen's edge where there is a home indicator; 8 pt above the edge
        // where the bottom safe area is zero.
        .padding(.bottom, bottomSafeArea > 0 ? -8 : 8)
        // iOS 26's keyboard is translucent: chrome left under it shows through below the keys.
        .opacity(isKeyboardUp || isHidden ? 0 : 1)
        .animation(.smooth(duration: 0.3), value: isHidden)
        .allowsHitTesting(shown != .hidden && !isKeyboardUp && !isHidden)
        // With nothing shown (under `tabs`, on a screen without a dock) the empty frame is
        // still an element, 24 × 44 at the bottom centre, which the accessibility audit
        // reported as having no description.
        .accessibilityHidden(isHidden || shown == .hidden)
    }

    // MARK: Keyboard

    private func keyboardShows() async {
        // In Split View the notification also comes for the other app's keyboard.
        let isLocalKey = UIResponder.keyboardIsLocalUserInfoKey
        let shows = NotificationCenter.default.notifications(named: UIResponder.keyboardWillShowNotification)
        for await isLocal in shows.map({ ($0.userInfo?[isLocalKey] as? Bool) ?? true }) where isLocal {
            isKeyboardUp = true
        }
    }

    private func keyboardHides() async {
        let hides = NotificationCenter.default.notifications(named: UIResponder.keyboardWillHideNotification)
        for await _ in hides.map({ _ in true }) {
            isKeyboardUp = false
        }
    }
}

nonisolated private enum ChromeShown: Equatable {
    case bar, dock, hidden
}

/// The bar or the top screen's dock, in one glass container whose shapes morph into each other.
private struct ChromeShapes<Bar: View>: View {
    let shown: ChromeShown
    let top: ChromeEntry?
    let bar: (BarControl?, @escaping (BarAction) -> Void) -> Bar

    @Namespace private var glass

    var body: some View {
        GlassGroup(spacing: ActionDock.spacing) {
            ZStack {
                switch shown {
                case .bar:
                    bar(top?.bar) { [actions = top?.barActions] in actions?.perform($0) }
                case .dock:
                    if let dock = top?.dock {
                        ActionDock(content: dock) { [actions = top?.dockActions] in actions?.perform($0) }
                    }
                case .hidden:
                    EmptyView()
                }
            }
            .frame(height: ActionDock.height)
        }
        .environment(\.chromeNamespace, glass)
    }
}

extension BottomChrome where Bar == EmptyView {
    /// A host with no bar: the side pane's stack, the gallery sheet's.
    init(router: StackRouter, @ViewBuilder content: () -> Content) {
        self.init(router: router, hasBar: false, content: content) { _, _ in EmptyView() }
    }
}
