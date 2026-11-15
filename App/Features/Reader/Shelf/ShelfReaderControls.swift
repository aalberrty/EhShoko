import EhCore
import EhFeatures
import SwiftUI

/// Shelf's reader controls (`shelf.md` section 5): a top group (Close, the title with the page,
/// Share and More) and a bottom panel (the strip of thumbnails, the slider, and Auto-play, the
/// reading direction and Settings), each in a glass container of its own.
///
/// Both stay in the hierarchy while hidden (`ReaderControlsLayer`), and slide a little as they
/// fade: the top group up, the panel down. They float over the engine without changing its
/// layout, so this design never sets the viewport, and showing or hiding them re-renders
/// nothing of the engine. The strip's thumbnails load while the panel shows.
struct ShelfReaderControls: View {
    let model: ReaderModel
    let viewport: ReaderViewport

    @Environment(SettingsStore.self) private var settings
    @State private var frame = ShelfReaderFrame()

    var body: some View {
        let isShown = model.showsPanel
        VStack(spacing: 0) {
            ReaderControlsLayer(isShown: isShown, spacing: ShelfReaderMetrics.topSpacing) {
                ShelfReaderTopBar(model: model, spreads: spreads)
            }
            .padding(.horizontal, ReaderMetrics.edgeInset)
            .padding(.top, ReaderMetrics.topInset)
            .offset(y: isShown ? 0 : -ShelfReaderMetrics.slide)

            Spacer(minLength: 0)

            ReaderControlsLayer(isShown: isShown) {
                ShelfReaderBottom(model: model, isReversed: settings.readingDirection == .rightToLeft)
            }
            .frame(maxWidth: ShelfReaderMetrics.panelMaximumWidth)
            .padding(.horizontal, ShelfReaderMetrics.panelInset)
            .padding(.bottom, frame.panelBottom)
            .offset(y: isShown ? 0 : ShelfReaderMetrics.slide)
        }
        // The panel sits as far from the bottom edge as from the sides where the screen has
        // room below the home indicator, so it measures from the edge itself.
        .ignoresSafeArea(.container, edges: .bottom)
        .onGeometryChange(for: ShelfReaderFrame.self) { ShelfReaderFrame($0) } action: { frame = $0 }
        .animation(.smooth(duration: 0.3), value: isShown)
        .background { ShelfStripThumbnailLoader(model: model) }
        .readerDestinationSheets(model)
    }

    /// Two pages side by side, as the engine decides it (`ReaderConfiguration.usesDualPage`):
    /// in a paged direction, with the setting on, on a screen wider than tall.
    private var spreads: ShelfReaderSpreads {
        ShelfReaderSpreads(
            offersDualPage: frame.isLandscape && settings.readingDirection != .vertical,
            enablesDualPage: settings.enablesDualPageMode,
            exceptCover: settings.exceptCover
        )
    }
}

/// Sizes of Shelf's controls, at the default text size.
nonisolated enum ShelfReaderMetrics {
    /// Between Close, the title capsule and the Share and More group.
    static let topSpacing: CGFloat = 8
    /// The panel's distance from the sides, and from the bottom where there is room.
    static let panelInset: CGFloat = 12
    /// In landscape and on wide screens the panel is centred at this width.
    static let panelMaximumWidth: CGFloat = 560
    static let panelCornerRadius: CGFloat = 34
    /// How far the groups slide while they fade in and out.
    static let slide: CGFloat = 40
}

/// What the controls take from the screen's shape: whether it is wider than tall, and how far
/// the panel stands from the bottom edge. Changes only when the screen turns.
nonisolated struct ShelfReaderFrame: Equatable {
    var isLandscape = false
    /// The bottom safe area less the panel's inset, so a panel above the home indicator sits
    /// concentric with the screen's corners; never less than the inset.
    var panelBottom: CGFloat = ShelfReaderMetrics.panelInset

    init() {}

    init(_ geometry: GeometryProxy) {
        isLandscape = geometry.size.width > geometry.size.height
        let safeBottom = geometry.safeAreaInsets.bottom
        panelBottom = max(safeBottom - ShelfReaderMetrics.panelInset, ShelfReaderMetrics.panelInset)
    }
}

/// Loads the strip's thumbnails while the panel shows: when it appears, when the reader moves
/// on and when a preview page arrives (`ReaderModel.loadStripThumbnails()`). A view of its own,
/// so these changes re-render nothing else. A gallery of one page has no strip.
private struct ShelfStripThumbnailLoader: View {
    let model: ReaderModel

    private struct Trigger: Equatable {
        let isShown: Bool
        let page: Int
        let knownThumbnails: Int
    }

    var body: some View {
        let trigger = Trigger(
            isShown: model.showsPanel && model.pageCount > 1,
            page: model.sliderPage,
            knownThumbnails: model.previewURLs.count
        )
        Color.clear
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onChange(of: trigger, initial: true) { _, trigger in
                if trigger.isShown {
                    model.loadStripThumbnails()
                }
            }
    }
}
