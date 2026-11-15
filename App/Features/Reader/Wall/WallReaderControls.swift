import EhCore
import EhFeatures
import SwiftUI

/// Wall's reader controls (`wall.md` section 5): Close at the top and one cluster under the
/// thumb, the scrub capsule beside More. While a finger is on the capsule a filmstrip of page
/// thumbnails stands above it.
///
/// Close, the capsule and More are glass shapes in one container, which stays in the hierarchy
/// while hidden (`ReaderControlsLayer`); they slide a little as they fade, Close up and the
/// cluster down. They float over the engine without changing its layout, so this design never
/// sets the viewport, and showing them or scrubbing re-renders nothing of the engine.
struct WallReaderControls: View {
    let model: ReaderModel
    let viewport: ReaderViewport

    @Environment(SettingsStore.self) private var settings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var frame = WallReaderFrame()

    var body: some View {
        let isShown = model.showsPanel
        let direction = settings.readingDirection
        // Reduce Motion: the controls cross-fade in place.
        let slide = reduceMotion ? 0 : WallReaderMetrics.slide
        ReaderControlsLayer(isShown: isShown, spacing: WallReaderMetrics.clusterSpacing) {
            VStack(spacing: 0) {
                ReaderCloseControl()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, ReaderMetrics.edgeInset)
                    .padding(.top, ReaderMetrics.topInset)
                    .offset(y: isShown ? 0 : -slide)

                Spacer(minLength: 0)

                WallReaderBottom(
                    model: model, isReversed: direction == .rightToLeft,
                    offersDualPage: frame.isLandscape && direction != .vertical
                )
                .padding(.bottom, frame.clusterBottom)
                .offset(y: isShown ? 0 : slide)
            }
        }
        // The cluster sits where the command bar does, partly below the safe area, so it
        // measures from the screen's edge.
        .ignoresSafeArea(.container, edges: .bottom)
        .onGeometryChange(for: WallReaderFrame.self) { WallReaderFrame($0) } action: { frame = $0 }
        .animation(.smooth(duration: 0.3), value: isShown)
        // Before the first scrub, which loads thumbnails for as many pages as this says.
        .onAppear { model.previewStripLength = WallReaderMetrics.filmLength }
        .readerDestinationSheets(model)
    }
}

/// The bottom of the controls: the filmstrip's place, the places kept for translation, and
/// the cluster.
private struct WallReaderBottom: View {
    let model: ReaderModel
    let isReversed: Bool
    let offersDualPage: Bool

    var body: some View {
        VStack(spacing: WallReaderMetrics.filmGap) {
            WallReaderFilmstrip(model: model, isReversed: isReversed)
            VStack(spacing: Tokens.Spacing.medium) {
                // A three-way pill (original, compare, translated) at the leading side and a
                // toast ("Translating page 23…") at the trailing side, once translation
                // exists. Not in the hierarchy until then.
                ReaderTranslationSlot(availability: model.translationAvailability) { EmptyView() }
                HStack(spacing: WallReaderMetrics.clusterSpacing) {
                    // Translate, a leading circle with a progress ring while a model downloads.
                    ReaderTranslationSlot(availability: model.translationAvailability) { EmptyView() }
                    WallReaderScrubCapsule(model: model, isReversed: isReversed)
                    WallReaderMoreMenu(model: model, offersDualPage: offersDualPage)
                        .glassSurface(in: .circle, isInteractive: true)
                }
            }
            .frame(maxWidth: WallReaderMetrics.clusterMaximumWidth)
            .padding(.horizontal, WallReaderMetrics.clusterInset)
        }
    }
}

/// Sizes of Wall's controls, at the default text size.
nonisolated enum WallReaderMetrics {
    /// The capsule and More are this high; More is a circle of it.
    static let clusterHeight: CGFloat = 52
    /// Between the capsule and More, and how near two shapes of the container blend.
    static let clusterSpacing: CGFloat = 8
    /// The cluster's distance from the sides.
    static let clusterInset: CGFloat = 12
    /// In landscape and on wide screens the cluster is centred at this width.
    static let clusterMaximumWidth: CGFloat = 560
    /// How far the cluster reaches below the safe area where the screen has a home indicator,
    /// and how far it stands from the edge where it has none: the command bar's place.
    static let clusterReach: CGFloat = 8
    /// Between the filmstrip's place and what is under it. The place keeps 8 pt of its own
    /// under the thumbnails, so they stand 16 pt above the cluster.
    static let filmGap: CGFloat = 8
    /// How many thumbnails the filmstrip shows.
    static let filmLength = 11
    /// How far Close and the cluster slide while they fade in and out.
    static let slide: CGFloat = 32
}

/// What the controls take from the screen's shape: whether it is wider than tall, and how far
/// the cluster stands from the bottom edge. Changes only when the screen turns.
nonisolated struct WallReaderFrame: Equatable {
    var isLandscape = false
    var clusterBottom: CGFloat = WallReaderMetrics.clusterReach

    init() {}

    init(_ geometry: GeometryProxy) {
        isLandscape = geometry.size.width > geometry.size.height
        let safeBottom = geometry.safeAreaInsets.bottom
        clusterBottom = safeBottom > 0
            ? max(safeBottom - WallReaderMetrics.clusterReach, WallReaderMetrics.clusterReach)
            : WallReaderMetrics.clusterReach
    }
}
