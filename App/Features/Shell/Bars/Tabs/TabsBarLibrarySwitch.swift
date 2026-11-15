import EhFeatures
import SwiftUI

/// The two screens of the Library tab.
nonisolated enum TabsBarLibrarySegment: Hashable, Sendable {
    case favorites
    case history
}

/// Which of its two screens the Library tab shows. The tab's root is not the only one that
/// chooses: a first screen's link to History selects the History segment from another tab, so
/// the choice is the bar's, kept by `TabsShell` and gone with it.
///
/// It is passed to the Library tab, never put into the environment: when the bar setting
/// changes, a copy of the tab view's environment outlives the tab view, and it would keep the
/// switch alive under the other bar.
@Observable
final class TabsBarLibrarySwitch {
    var segment = TabsBarLibrarySegment.favorites
}

/// Shows History where the tabs bar keeps it: the Library tab, at its root, on its History
/// segment.
///
/// A screen reads `\.showLibraryHistory` and calls it. Under `command` there is no Library tab
/// and it does nothing and answers `false`: History is a place there, which the caller opens
/// with `AppRouter.go(to:start:)`.
///
/// Equal when it acts on the same router and switch, so the screens that read it are not drawn
/// again each time the shell's body runs. It holds both weakly, because an environment value
/// can outlive the tab view it was set on (see `TabsBarLibrarySwitch`).
nonisolated struct TabsBarHistoryOpener: Equatable {
    private weak var router: AppRouter?
    private weak var library: TabsBarLibrarySwitch?

    /// `TabsShell` passes its router and the switch it owns; `nil` is the opener that does
    /// nothing.
    init(router: AppRouter?, library: TabsBarLibrarySwitch?) {
        self.router = router
        self.library = library
    }

    /// Whether the tabs bar was there to show it.
    @MainActor
    @discardableResult
    func callAsFunction() -> Bool {
        guard let router, let library else { return false }
        library.segment = .history
        // The switch is on the tab's root, beside no gallery of the other segment.
        router.library.popToRoot()
        router.library.closeSidePane()
        if router.selectedTab != .library {
            router.select(.library)
        }
        return true
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.router === rhs.router && lhs.library === rhs.library
    }
}

extension EnvironmentValues {
    /// Set by `TabsShell` on every tab. Without the tabs bar it does nothing.
    @Entry var showLibraryHistory = TabsBarHistoryOpener(router: nil, library: nil)
}
