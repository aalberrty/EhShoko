import EhCore
import EhFeatures
import SwiftUI

// Continue on iOS 18 and iOS 26.0, which have no accessory that can be switched off without
// rebuilding every tab: the accessory's content in a capsule above the tab bar. As the bottom
// chrome does with the bar and docks, each tab's stack has one capsule, drawn over the stack
// (`TabsBarLegacyCapsuleHost`), and each screen keeps its height free inside the stack
// (`TabsBarLegacyAccessory`). It follows the accessory of the later systems wherever it can:
// it stays where it is across pushes, it is absent on gallery pages, on the search surface and
// beside a side gallery, present on the results pushed over the surface, and out of the way of
// a keyboard.

extension EnvironmentValues {
    /// Whether the screens of this stack are under the tab bar and so show the capsule that
    /// stands in for the accessory: true for the tabs' stacks, false everywhere else.
    @Entry var tabsBarKeepsLegacyAccessory = false

    /// Whether this stack's root is the search surface, which never shows Continue.
    @Entry var tabsBarHoldsSearchSurface = false

    /// The bottom edge of the tab a screen is in. Set by `TabsBarStack` on the systems that
    /// draw the capsule; elsewhere it stays empty.
    @Entry var tabsBarLegacyEdge = TabsBarLegacyEdge()
}

/// What a capsule needs to know of the bottom of its tab, which only the tab can measure.
nonisolated struct TabsBarLegacyEdge: Equatable, Sendable {
    /// The bottom safe area of the tab's content: the home indicator and, while it shows, the
    /// tab bar; a keyboard's height while one is up.
    var inset: CGFloat = 0
    /// A keyboard covers the bottom of the tab. The accessory of the later systems stays
    /// under it; a capsule in a bottom inset would ride above it, over a list's find field.
    var isKeyboardUp = false
}

/// Around one tab's stack, on the systems that draw the capsule: measures the tab's bottom
/// edge for its screens, and draws the capsule over the stack. On the later systems it adds
/// nothing.
struct TabsBarLegacyEdgeReader: ViewModifier {
    let tab: AppTab

    func body(content: Content) -> some View {
        // The same for the whole life of the process, so this `if` never rebuilds a tab.
        if TabAccessoryKind.usesSystemAccessory {
            content
        } else {
            content
                .modifier(TabsBarLegacyCapsuleHost(tab: tab))
                .modifier(TabsBarLegacyEdgeMeasure())
        }
    }
}

/// The capsule of one tab, over its stack and above the tab bar. It is placed from the tab's
/// own bottom edge, which is right at once, where a screen's can lag behind (see `lift`), and
/// it stays where it is while screens are pushed and popped under it.
private struct TabsBarLegacyCapsuleHost: ViewModifier {
    let tab: AppTab

    @Environment(AppRouter.self) private var appRouter
    @Environment(ContinueModel.self) private var continueModel
    @Environment(SettingsStore.self) private var settings
    @Environment(\.tabsBarLegacyEdge) private var edge
    @Environment(\.horizontalSizeClass) private var sizeClass

    func body(content: Content) -> some View {
        let isVisible = isVisible
        content.overlay(alignment: .bottom) {
            ZStack {
                if isVisible {
                    TabsBarAccessory()
                        .legacyTabAccessoryCapsule()
                        .transition(.opacity)
                }
            }
            // Under a keyboard it fades where it is instead of riding up.
            .ignoresSafeArea(.keyboard, edges: .bottom)
            .animation(.smooth(duration: 0.25), value: isVisible)
        }
    }

    /// What the accessory host of the later systems decides (`TabsBarAccessoryHost`), for this
    /// tab: on while something is in progress and the top screen keeps the tab bar, off beside
    /// a side gallery, while Ledger's Index column shows Continue itself (on while the Index
    /// is hidden), on the search surface, and while a keyboard is up.
    private var isVisible: Bool {
        guard continueModel.first != nil, !edge.isKeyboardUp else { return false }
        let stack = appRouter.stack(for: tab)
        let showsSearchSurface = tab == .search && stack.isAtRoot
        let showsLeadingColumn = tab == .home && sizeClass == .regular && StartStructure.hasLeadingColumn(settings)
            && !stack.isLeadingColumnHidden
        return !stack.hidesBrowseChrome && stack.sideGallery == nil && !showsSearchSurface && !showsLeadingColumn
    }
}

private struct TabsBarLegacyEdgeMeasure: ViewModifier {
    @State private var inset: CGFloat = 0
    /// The same edge without a keyboard: a view that ignores the keyboard keeps it.
    @State private var restingInset: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .environment(\.tabsBarLegacyEdge, TabsBarLegacyEdge(inset: inset, isKeyboardUp: inset > restingInset + 1))
            .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.bottom } action: { inset = $0 }
            .background {
                Color.clear
                    .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.bottom } action: { restingInset = $0 }
                    .ignoresSafeArea(.keyboard, edges: .bottom)
            }
    }
}

/// On every screen of every stack (`RoutedStack`). On iOS 18 and iOS 26.0, under the tab
/// bar, it keeps the capsule's height free at the bottom of the screens that keep the bar. On
/// later systems and under `command` it adds nothing: no view, no state.
struct TabsBarLegacyAccessory: ViewModifier {
    /// Whether this screen's route keeps the tab bar.
    let isAllowed: Bool

    @Environment(\.tabsBarKeepsLegacyAccessory) private var keepsAccessory

    func body(content: Content) -> some View {
        // Neither changes while a screen exists: the system is the process's, and a screen
        // is in a tab's stack for as long as it lives (changing the bar rebuilds every
        // screen). So this `if` never rebuilds one.
        if keepsAccessory, !TabAccessoryKind.usesSystemAccessory {
            content.modifier(TabsBarCapsuleRoom(isAllowed: isAllowed))
        } else {
            content
        }
    }
}

private struct TabsBarCapsuleRoom: ViewModifier {
    let isAllowed: Bool

    /// This screen's own bottom safe area, outside the room it keeps.
    @State private var screenInset: CGFloat = 0
    @Environment(\.tabsBarHoldsSearchSurface) private var holdsSearchSurface
    @Environment(\.tabsBarLegacyEdge) private var edge
    @Environment(\.chrome) private var chrome
    @Environment(\.isPresented) private var isPushed
    @Environment(StackRouter.self) private var stack
    @Environment(ContinueModel.self) private var continueModel: ContinueModel?

    func body(content: Content) -> some View {
        let isUnderBar = isUnderBar
        content
            // Always present, so a change of room never changes the screen's structure.
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Color.clear.frame(height: isUnderBar ? room + lift : 0)
            }
            .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.bottom } action: { inset in
                if isUnderBar { screenInset = inset }
            }
    }

    /// A screen of a tab's own stack whose route keeps the tab bar. The side pane's screens
    /// are inside a tab too, beside the list that has the capsule.
    private var isUnderBar: Bool {
        isAllowed && !chrome.isSidePane
    }

    /// The capsule's height while the tab's host draws it over this screen: the same rule, from
    /// this screen's side. What is in progress is read last, and so only where a capsule can
    /// show: on gallery pages a change of it redraws no screen.
    private var room: CGFloat {
        // Beside Ledger's Index column the column has Continue (`continueIsInChrome` is off
        // until the Index is hidden); beside a side gallery the capsule is off, as the
        // accessory is on the later systems.
        guard chrome.continueIsInChrome, !edge.isKeyboardUp, stack.sideGallery == nil else { return 0 }
        // The search surface is its stack's root, which nothing presents; a pushed screen
        // is presented.
        if holdsSearchSurface, !isPushed { return 0 }
        return continueModel?.first != nil ? LegacyTabAccessoryMetrics.room : 0
    }

    /// How far this screen's content is lifted over a tab bar the screen has not noticed. On
    /// iOS 26.0 a screen keeps the bottom safe area it had when the bar's visibility last
    /// changed: a list pushed over a gallery, or uncovered by Back from one, is laid out as if
    /// the bar were still hidden until something else lays it out again, and its last rows sit
    /// behind the bar. The tab's own edge is right at once, so the difference is what is
    /// missing. It goes when the screen catches up.
    private var lift: CGFloat {
        let missing = edge.inset - screenInset
        // The two are measured on either side of the stack and differ by a fraction.
        return missing > 2 ? missing : 0
    }
}
