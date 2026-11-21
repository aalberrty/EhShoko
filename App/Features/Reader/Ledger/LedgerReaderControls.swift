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
        .background { LedgerTranslationPresence(model: model, sheet: sheet) }
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
    /// size, the two-page rows in landscape), up to `LedgerSheetHeights.maximumOpen`.
    private(set) var openHeight: CGFloat
    /// Whether the reader's screen is wider than tall. The sheet cannot see that itself.
    private(set) var isLandscape = false
    /// Auto-play's interval while it is off: the switch turns it on at this.
    private(set) var autoPlayInterval: ReaderAutoPlayPolicy = .fiveSeconds
    /// Where the sheet's top edge is in the window, in whole points; `nil` until it is laid
    /// out. In regular width the system floats the sheet as a card above the screen's bottom
    /// edge, where its own heights do not say what it covers.
    var top: CGFloat?

    /// Whether the open rows hold the translation group: where the gallery offers Translate,
    /// which most do (and every gallery until its language is known).
    private(set) var showsTranslation = true

    private let hasPages: Bool
    /// The reader's screen's height, in portrait or landscape as it stands; 0 until measured.
    @ObservationIgnored private var screenHeight: CGFloat = 0
    @ObservationIgnored private var defaultOpenHeight: CGFloat
    @ObservationIgnored private var maximumOpenHeight: CGFloat
    private let minimumOpenHeight: CGFloat

    init(hasPages: Bool) {
        self.hasPages = hasPages
        let heights = LedgerSheetHeights(hasPages: hasPages, showsTranslation: true)
        openHeight = heights.open
        defaultOpenHeight = heights.open
        maximumOpenHeight = LedgerSheetHeights.maximumOpen(hasPages: hasPages, showsTranslation: true)
        // Always a pull above the resting height, so the two never meet.
        minimumOpenHeight = heights.rest + LedgerReaderMetrics.minimumPull
    }

    /// The reader's screen turned or changed size. The open rows differ between portrait and
    /// landscape (landscape adds the two-page rows), and in portrait the open sheet takes at
    /// most a share of the screen, so the open height starts over from what portrait needs and
    /// follows the rows from there.
    func screenDidChange(isLandscape: Bool, height: CGFloat) {
        guard isLandscape != self.isLandscape || height != screenHeight else { return }
        self.isLandscape = isLandscape
        screenHeight = height
        resetOpenHeight()
    }

    /// The translation group came or went (a gallery's language became known, `README` 8).
    /// The open height starts over from what the rows need with or without it.
    func translationDidChange(isShown: Bool) {
        guard isShown != showsTranslation else { return }
        showsTranslation = isShown
        resetOpenHeight()
    }

    private func resetOpenHeight() {
        maximumOpenHeight = LedgerSheetHeights.maximumOpen(
            hasPages: hasPages, showsTranslation: showsTranslation,
            screenHeight: screenHeight, isLandscape: isLandscape
        )
        let rows = LedgerSheetHeights(hasPages: hasPages, showsTranslation: showsTranslation).open
        defaultOpenHeight = max(min(rows, maximumOpenHeight), minimumOpenHeight)
        openHeight = defaultOpenHeight
    }

    /// The open rows were laid out `height` tall.
    func openRowsDidLayOut(height: CGFloat) {
        let fitted = min(max(height.rounded(.up), minimumOpenHeight), maximumOpenHeight)
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
/// the vertical direction the strip scrolls behind the sheet (and only the closing page makes
/// room, `coveredBottom`), and in landscape there is no room above it.
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
    /// In regular width: from the sheet's top edge to the screen's bottom edge, at rest or
    /// open, wherever the system has put the card. Unused in compact width.
    var floatingCover: CGFloat = 0

    var value: CGFloat {
        isShown && isOpen && isPaged && isPortrait && isCompactWidth ? covered : 0
    }

    /// What the sheet covers while the engine keeps drawing under it, which the closing page
    /// keeps as room under its column so that it rises above the sheet.
    ///
    /// - Compact width: the open sheet in the vertical direction, in portrait, where the strip
    ///   scrolls behind it. In landscape the open sheet leaves no room above it.
    /// - Regular width: the floating card, at rest or open, in every direction and
    ///   orientation. The engine is never shortened there, and the card sits higher than the
    ///   room the closing page keeps for controls resting at the bottom.
    var coveredBottom: CGFloat {
        guard isShown else { return 0 }
        guard isCompactWidth else { return floatingCover }
        return isOpen && !isPaged && isPortrait ? covered : 0
    }

    private var covered: CGFloat { (openHeight + safeAreaBottom).rounded() }
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
        let isCompactWidth = horizontalSizeClass == .compact
        let page = LedgerPageInset(
            isShown: model.showsPanel, isOpen: sheet.isOpen, isPaged: settings.readingDirection != .vertical,
            isPortrait: !screen.isLandscape, isCompactWidth: isCompactWidth,
            openHeight: sheet.openHeight, safeAreaBottom: screen.safeAreaBottom,
            // Read only in regular width, so that the sheet's top moving under a finger
            // re-renders nothing on a phone.
            floatingCover: isCompactWidth ? 0 : screen.cover(below: sheet.top)
        )
        let inset = page.value
        let covered = page.coveredBottom
        Color.clear
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onGeometryChange(for: LedgerScreenShape.self) { LedgerScreenShape($0) } action: { shape in
                screen = shape
                sheet.screenDidChange(isLandscape: shape.isLandscape, height: shape.height)
            }
            .onChange(of: inset, initial: true) { _, inset in
                set(inset)
            }
            // Not animated: only the closing page reads it, and the strip moves to keep it in view.
            .onChange(of: covered, initial: true) { _, covered in
                viewport.coveredBottom = covered
            }
            .onDisappear {
                set(0)
                viewport.coveredBottom = 0
            }
    }

    private func set(_ inset: CGFloat) {
        guard viewport.bottomInset != inset else { return }
        withAnimation(LedgerReaderMetrics.pageAnimation) {
            viewport.bottomInset = inset
        }
    }
}

/// What the controls take from the reader's screen: whether it is wider than tall, the safe
/// area at its bottom, which is also under the sheet, where its bottom edge is in the window,
/// and its height, safe areas included. Changes only when the screen turns or changes size.
nonisolated struct LedgerScreenShape: Equatable {
    var isLandscape = false
    var safeAreaBottom: CGFloat = 0
    var bottom: CGFloat = 0
    var height: CGFloat = 0

    init() {}

    init(_ geometry: GeometryProxy) {
        isLandscape = geometry.size.width > geometry.size.height
        safeAreaBottom = geometry.safeAreaInsets.bottom
        let frame = geometry.frame(in: .global)
        bottom = (frame.maxY + geometry.safeAreaInsets.bottom).rounded()
        height = (bottom - (frame.minY - geometry.safeAreaInsets.top)).rounded()
    }

    /// From a sheet's top edge, in the window, to the screen's bottom edge.
    func cover(below top: CGFloat?) -> CGFloat {
        guard let top, bottom > 0 else { return 0 }
        return max(bottom - top, 0)
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
