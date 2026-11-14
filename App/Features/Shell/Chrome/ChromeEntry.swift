import EhFeatures
import SwiftUI

// How a screen tells the bottom chrome what to show (`Design/designs/spikes/S2.md`
// sections 1 and 8). A screen declares values with `.dock(_:perform:)` and
// `.barControl(_:perform:)`; the shell's wrapper stamps one entry per screen with the screen's
// route; the host around the stack (`BottomChrome`) takes the top route's entry.

/// The newest closure that performs a screen's dock actions. A reference, and not observable:
/// the preference value must be `Equatable`, which a closure is not, and replacing the closure
/// on every `body` must not change the value.
final class DockActions {
    var perform: (DockAction) -> Void = { _ in }
}

/// The same for a screen's control in the bar.
final class BarActions {
    var perform: (BarAction) -> Void = { _ in }
}

/// What one screen of a stack declares for the bottom chrome.
nonisolated struct ChromeEntry: Equatable {
    /// The screen's route; `nil` for the stack's root. Stamped by the shell, never by a part.
    var route: Route?
    var dock: DockContent?
    var dockActions: DockActions?
    var bar: BarControl?
    var barActions: BarActions?

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.route == rhs.route && lhs.dock == rhs.dock && lhs.dockActions === rhs.dockActions
            && lhs.bar == rhs.bar && lhs.barActions === rhs.barActions
    }
}

/// Every screen of a stack contributes, covered or not, in path order, and a popped screen's
/// entry stays until its pop has finished. That is why entries carry their route.
nonisolated struct ChromeKey: PreferenceKey {
    static var defaultValue: [ChromeEntry] { [] }

    static func reduce(value: inout [ChromeEntry], nextValue: () -> [ChromeEntry]) {
        value.append(contentsOf: nextValue())
    }
}

extension EnvironmentValues {
    /// The height a screen keeps free at its bottom for the chrome over it. Set by
    /// `BottomChrome`; zero while a keyboard is up, when the keyboard takes the chrome's place.
    @Entry var chromeReserve: CGFloat = 0
}

extension View {
    /// Declares this screen's bottom actions. The shell draws them, in the bar's place, under
    /// either bar, in the side pane and in the gallery sheet; a part never draws a bottom bar.
    /// `nil` declares none (a page that has not loaded). `perform` may capture anything: only
    /// a change of `content` reaches the chrome.
    func dock(_ content: DockContent?, perform: @escaping (DockAction) -> Void) -> some View {
        modifier(DockDeclaration(content: content, perform: perform))
    }

    /// Declares what this screen puts in the command bar's trailing circle: a list's filter or
    /// sort, Ledger's paste button. Under `tabs`, in the side pane and in the gallery sheet
    /// there is no bar and nothing is drawn, so a part that needs the control visible there
    /// draws it itself (`ChromeContext.barHoldsPrimaryControl`).
    func barControl(_ control: BarControl?, perform: @escaping (BarAction) -> Void) -> some View {
        modifier(BarControlDeclaration(control: control, perform: perform))
    }

    /// Around every screen of a stack (`RoutedStack` applies it to its root and to each
    /// destination): keeps the chrome's height free inside the screen, where the inset reaches
    /// the screen's scroll view, and reduces what the screen declared to one stamped entry.
    func chromeScreen(_ route: Route?) -> some View {
        modifier(ChromeScreen(route: route))
    }
}

private struct DockDeclaration: ViewModifier {
    let content: DockContent?
    let perform: (DockAction) -> Void
    @State private var actions = DockActions()

    func body(content view: Content) -> some View {
        // The newest closure, without invalidating anything.
        let _ = (actions.perform = perform)
        view.preference(
            key: ChromeKey.self, value: [ChromeEntry(dock: content, dockActions: content == nil ? nil : actions)]
        )
    }
}

private struct BarControlDeclaration: ViewModifier {
    let control: BarControl?
    let perform: (BarAction) -> Void
    @State private var actions = BarActions()

    func body(content view: Content) -> some View {
        let _ = (actions.perform = perform)
        view.preference(
            key: ChromeKey.self, value: [ChromeEntry(bar: control, barActions: control == nil ? nil : actions)]
        )
    }
}

private struct ChromeScreen: ViewModifier {
    let route: Route?
    @Environment(\.chromeReserve) private var reserve

    func body(content: Content) -> some View {
        content
            // Clear: the chrome itself is an overlay on the stack, because an inset added
            // outside a `NavigationStack` does not reach the scroll views inside it. On iOS 26
            // this also gives the screen's scroll view its soft edge under the chrome. With
            // nothing to keep free the bar has no content and draws nothing.
            .bottomBar(spacing: 0) {
                if reserve > 0 {
                    Color.clear.frame(height: reserve)
                }
            }
            // Exactly one entry per screen, so the host can tell "the top screen wants no
            // dock" from "the top screen has not reported yet". Of several declarations in
            // one screen (a first screen around a list) the innermost, last, wins.
            .transformPreference(ChromeKey.self) { entries in
                var stamped = ChromeEntry(route: route)
                for entry in entries {
                    if let dock = entry.dock {
                        stamped.dock = dock
                        stamped.dockActions = entry.dockActions
                    }
                    if let bar = entry.bar {
                        stamped.bar = bar
                        stamped.barActions = entry.barActions
                    }
                }
                entries = [stamped]
            }
    }
}
