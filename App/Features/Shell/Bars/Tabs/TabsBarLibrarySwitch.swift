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
/// Only `TabsShell` holds it. It is handed to the Library tab's root as a value and to the
/// opener weakly, never put into the environment: a copy of the tab view's environment
/// outlives the tab view when the bar is changed, and would keep it alive under the other bar.
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
nonisolated struct TabsBarHistoryOpener {
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
}

extension EnvironmentValues {
    /// Set by `TabsShell` on every tab. Without the tabs bar it does nothing.
    @Entry var showLibraryHistory = TabsBarHistoryOpener(router: nil, library: nil)
}
