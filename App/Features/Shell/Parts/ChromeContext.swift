import EhModels
import SwiftUI

/// What surrounds a screen, as far as a part may know it (`Design/designs/README.md`
/// section 5). The shell sets it once per stack; it changes only when the bar setting or the
/// presentation does, so reading it costs a screen nothing while it scrolls.
///
/// A part reads it for the few things that depend on its surroundings: whether to draw
/// Continue, whether its primary list control is in the bar, whether it has a Back button.
/// It never reads which design surrounds it.
nonisolated struct ChromeContext: Equatable, Sendable {
    /// The bottom bar the user chose.
    var bar: BarStyle
    /// Whether the bar's chrome already shows Continue (the tab bar's accessory). A first
    /// screen draws its own Continue only when this is false. Under `tabs` it is true, except
    /// beside Ledger's Index column on regular width, where the accessory is off and the Index
    /// keeps its card (`spikes/S5.md` section 4.5).
    var continueIsInChrome: Bool
    /// The screen is in the trailing side pane: no Back on its root, no zoom, a narrow column.
    var isSidePane = false
    /// The screen is in the gallery sheet opened from a link.
    var isSheet = false
    /// The screen is the leading column beside the stack: Ledger's Index on regular width.
    var isLeadingColumn = false

    init(
        bar: BarStyle, continueIsInChrome: Bool? = nil, isSidePane: Bool = false, isSheet: Bool = false,
        isLeadingColumn: Bool = false
    ) {
        self.bar = bar
        self.continueIsInChrome = continueIsInChrome ?? (bar == .tabs)
        self.isSidePane = isSidePane
        self.isSheet = isSheet
        self.isLeadingColumn = isLeadingColumn
    }

    /// Whether the command bar is under this screen and draws its primary list control (the
    /// filter, else the sort) in its trailing circle. When false (under `tabs`, in the side
    /// pane, in the gallery sheet) a list draws that control in its own header line.
    var barHoldsPrimaryControl: Bool {
        bar == .command && !isSidePane && !isSheet
    }

    /// The pane's and the gallery sheet's stacks: the same bar setting, another presentation.
    func presented(isSidePane: Bool = false, isSheet: Bool = false) -> ChromeContext {
        ChromeContext(
            bar: bar, continueIsInChrome: continueIsInChrome, isSidePane: isSidePane, isSheet: isSheet
        )
    }
}

extension EnvironmentValues {
    /// Set by the shell on every stack. The default is the default preset's.
    @Entry var chrome = ChromeContext(bar: .tabs)
}
