import EhCore
import EhFeatures
import SwiftUI

/// Ledger's reader controls (`ledger.md` section 5): Close in the top leading corner and one
/// system sheet with two heights. The sheet is not modal: the page behind it scrolls, zooms
/// and turns as usual, and a tap in the middle of the page hides and shows the sheet and Close
/// together.
///
/// The sheet is the system's, so on iOS 26 it is glass, and what sits on it is fills. Close is
/// the one custom glass shape; it is in the reader's own view, where it stays reachable above
/// the sheet.
///
/// At its open height the sheet would cover the lower half of the page, so in a paged
/// direction, in portrait, the engine gives up that room: this is the design that sets the
/// viewport's inset (spike S4). Nothing else of the engine is touched, so showing, hiding or
/// dragging the sheet re-renders nothing of it.
struct LedgerReaderControls: View {
    let model: ReaderModel
    let viewport: ReaderViewport

    /// What the sheet keeps while it is hidden. It belongs to this view, so it goes when the
    /// design does.
    @State private var sheet: LedgerSheetState

    init(model: ReaderModel, viewport: ReaderViewport) {
        self.model = model
        self.viewport = viewport
        _sheet = State(initialValue: LedgerSheetState(hasPages: model.pageCount > 1))
    }

    var body: some View {
        @Bindable var model = model
        let isShown = model.showsPanel
        ReaderControlsLayer(isShown: isShown) {
            ReaderCloseControl()
        }
        .padding(.leading, ReaderMetrics.edgeInset)
        .padding(.top, ReaderMetrics.topInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .animation(.smooth(duration: 0.3), value: isShown)
        .background { LedgerPageInsetDriver(model: model, viewport: viewport, sheet: sheet) }
        .background { LedgerScreenDestinations(model: model) }
        // Closing needs nothing taken down first: the sheet leaves with the reader (spike S4).
        .sheet(isPresented: $model.showsPanel) {
            LedgerReaderSheet(model: model, sheet: sheet)
        }
    }
}

/// What Ledger's sheet keeps for as long as the reader is open under this design. The sheet
/// is taken down and put up again with every tap in the middle of the page, and comes back as
/// it was left.
@Observable
final class LedgerSheetState {
    /// Whether the open height is the chosen one.
    var isOpen = false
    /// The open height, above the safe area: what the open rows need. It starts at what they
    /// need at the default text size and follows them once they are laid out (a larger text
    /// size, the two-page rows in landscape), up to the height that was drawn.
    private(set) var openHeight: CGFloat
    /// Whether the reader's screen is wider than tall. The sheet cannot see that itself.
    private(set) var isLandscape = false
    /// Auto-play's interval while it is off: the switch turns it on at this.
    private(set) var autoPlayInterval: ReaderAutoPlayPolicy = .fiveSeconds

    private let defaultOpenHeight: CGFloat
    private let minimumOpenHeight: CGFloat

    init(hasPages: Bool) {
        let heights = LedgerSheetHeights(hasPages: hasPages)
        openHeight = heights.open
        defaultOpenHeight = heights.open
        // Always a pull above the resting height, so the two never meet.
        minimumOpenHeight = heights.rest + LedgerReaderMetrics.minimumPull
    }

    /// The reader's screen turned. The open rows differ between the two (landscape adds the
    /// two-page rows), so the open height starts over from what portrait needs and follows the
    /// rows from there.
    func screenDidTurn(isLandscape: Bool) {
        guard isLandscape != self.isLandscape else { return }
        self.isLandscape = isLandscape
        openHeight = defaultOpenHeight
    }

    /// The open rows were laid out `height` tall.
    func openRowsDidLayOut(height: CGFloat) {
        let fitted = min(max(height.rounded(.up), minimumOpenHeight), LedgerReaderMetrics.maximumOpenHeight)
        if abs(fitted - openHeight) >= 1 {
            openHeight = fitted
        }
    }

    /// Auto-play as chosen in a menu: an interval is also remembered for the switch.
    func setAutoPlay(_ policy: ReaderAutoPlayPolicy, of model: ReaderModel) {
        if policy != .off {
            autoPlayInterval = policy
        }
        model.setAutoPlay(policy)
    }

    /// The interval chosen in the open sheet's row. It applies at once while auto-play runs.
    func setAutoPlayInterval(_ interval: ReaderAutoPlayPolicy, of model: ReaderModel) {
        guard interval != .off else { return }
        autoPlayInterval = interval
        if model.autoPlay != .off {
            model.setAutoPlay(interval)
        }
    }
}

/// How much of the screen's bottom the page gives up (spike S4): what the open sheet covers,
/// and only while the controls show, at the open height, in a paged direction, in portrait on
/// a screen of compact width. Otherwise nothing: at rest the sheet covers the page's foot, in
/// the vertical direction the strip scrolls behind the sheet, and in landscape there is no
/// room above it.
///
/// What the sheet covers is its open height and the safe area under it: sizes, never the
/// sheet's position, which has values in flight while the system moves it. So the inset has
/// two values and changes in one animation, which the engine follows frame by frame.
nonisolated struct LedgerPageInset: Equatable {
    var isShown: Bool
    var isOpen: Bool
    var isPaged: Bool
    var isPortrait: Bool
    /// Where the sheet is attached to the bottom edge. In regular width the system may show it
    /// as a card in the middle of the screen (an iPad), which covers no foot of the page.
    var isCompactWidth: Bool
    var openHeight: CGFloat
    var safeAreaBottom: CGFloat

    var value: CGFloat {
        isShown && isOpen && isPaged && isPortrait && isCompactWidth ? (openHeight + safeAreaBottom).rounded() : 0
    }
}

/// Sets the viewport's inset: one animated change whenever what decides it changes, and back
/// to nothing when the design goes away. A view of its own, behind the controls and of their
/// size, so that these changes re-render nothing else.
private struct LedgerPageInsetDriver: View {
    let model: ReaderModel
    let viewport: ReaderViewport
    let sheet: LedgerSheetState

    @Environment(SettingsStore.self) private var settings
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var screen = LedgerScreenShape()

    var body: some View {
        let inset = LedgerPageInset(
            isShown: model.showsPanel, isOpen: sheet.isOpen, isPaged: settings.readingDirection != .vertical,
            isPortrait: !screen.isLandscape, isCompactWidth: horizontalSizeClass == .compact,
            openHeight: sheet.openHeight, safeAreaBottom: screen.safeAreaBottom
        ).value
        Color.clear
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onGeometryChange(for: LedgerScreenShape.self) { LedgerScreenShape($0) } action: { shape in
                screen = shape
                sheet.screenDidTurn(isLandscape: shape.isLandscape)
            }
            .onChange(of: inset, initial: true) { _, inset in
                set(inset)
            }
            .onDisappear { set(0) }
    }

    private func set(_ inset: CGFloat) {
        guard viewport.bottomInset != inset else { return }
        withAnimation(LedgerReaderMetrics.pageAnimation) {
            viewport.bottomInset = inset
        }
    }
}

/// What the controls take from the reader's screen: whether it is wider than tall, and the
/// safe area at its bottom, which is also under the sheet. Changes only when the screen turns.
nonisolated struct LedgerScreenShape: Equatable {
    var isLandscape = false
    var safeAreaBottom: CGFloat = 0

    init() {}

    init(_ geometry: GeometryProxy) {
        isLandscape = geometry.size.width > geometry.size.height
        safeAreaBottom = geometry.safeAreaInsets.bottom
    }
}

/// The reading settings and the share sheet while the control sheet is down: a page's
/// long-press menu can ask for the share sheet then. While the control sheet is up they are
/// presented from inside it, because a second sheet on the reader's screen would wait until
/// the control sheet went away (spike S4).
private struct LedgerScreenDestinations: View {
    let model: ReaderModel

    var body: some View {
        if !model.showsPanel {
            Color.clear
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                .readerDestinationSheets(model)
        }
    }
}
