import EhCore
import EhFeatures
import EhModels
import SwiftUI

/// What is at the root before, or above, the first list (`Design/designs/README.md`
/// sections 4 and 5.2). The first screen part's switch point: it takes no parameters and
/// reads `designStart`.
///
/// A first screen relies on its surroundings only through the contract: under `tabs` it is
/// the Home tab's root and `chrome.continueIsInChrome` tells it not to draw Continue; under
/// `command` the bar sits below it and the place menu moves between places with
/// `AppRouter.go(to:start:)`.
struct StartScreen: View {
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        switch settings.designStart {
        case .shelf: ShelfHomeView()
        case .wall: WallStartView()
        case .ledger: LedgerIndexView()
        }
    }
}

/// What the shell's structure needs to know of the first screen. The bars and the stack's
/// host ask here, so `designStart` is read in this file and nowhere else.
enum StartStructure {
    /// The first screen's design, for `AppRouter.go(to:start:)` and the place menu's entries.
    static func style(_ settings: SettingsStore) -> DesignStyle {
        settings.designStart
    }

    /// Whether the first screen stands beside the stack as a leading column on regular width:
    /// Ledger's Index (`README.md` section 5.8, rule 2). It decides the tab view's style too,
    /// from the setting alone and never from the width.
    static func hasLeadingColumn(_ settings: SettingsStore) -> Bool {
        settings.designStart == .ledger
    }

    /// The Index column's width.
    static let leadingColumnWidth: CGFloat = 280
}
