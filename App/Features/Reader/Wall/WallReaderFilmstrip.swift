import EhFeatures
import SwiftUI

/// The filmstrip's place above the cluster. The strip is there only while a finger scrubs:
/// eleven thumbnails around the needle's page, the one under the needle larger and outlined,
/// fading towards the screen's edges. It follows the reading direction.
///
/// The place keeps its height, so the strip coming and going moves nothing, and it never
/// takes a touch: the page under it turns as usual. The thumbnails are content, not glass.
struct WallReaderFilmstrip: View {
    let model: ReaderModel
    let isReversed: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let isUp = model.showsSliderPreview
        Color.clear
            .frame(height: Self.height)
            .overlay(alignment: .bottom) {
                if isUp {
                    WallReaderFilm(model: model, isReversed: isReversed)
                        .transition(arrival)
                }
            }
            .animation(.snappy(duration: 0.25), value: isUp)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    /// The strip rises as it fades in. Reduce Motion: it fades in place.
    private var arrival: AnyTransition {
        reduceMotion ? .opacity : .offset(y: Self.rise).combined(with: .opacity)
    }

    /// Above and below the thumbnails, for their shadow.
    static let shadowRoom: CGFloat = 8
    /// The current thumbnail, which is the tallest (50 pt wide), and the shadow's room.
    private static let height: CGFloat = 70 + shadowRoom * 2
    /// How far the strip rises as it appears.
    private static let rise: CGFloat = 24
}

/// The strip itself, built once per scrub.
private struct WallReaderFilm: View {
    let model: ReaderModel
    let isReversed: Bool

    /// Eleven thumbnails are wider than a phone: the strip is centred and the screen cuts it.
    /// On a wider screen it fades over its own width.
    private static let maximumWidth: CGFloat = 440
    private static let fade = Gradient(stops: [
        .init(color: .clear, location: 0),
        .init(color: .black, location: 0.18),
        .init(color: .black, location: 0.82),
        .init(color: .clear, location: 1),
    ])

    var body: some View {
        ReaderThumbnailStrip(
            model: model, length: WallReaderMetrics.filmLength, isReversed: isReversed,
            // The outline is white in both appearances: it rings a picture, over a page.
            width: 34, currentWidth: 50, outline: .white, outlineOffset: 1, spacing: 5,
            // The thumbnails stand on one line, the larger one rising above the others.
            alignment: .bottom
        )
        .fixedSize()
        .frame(maxWidth: Self.maximumWidth)
        // Room for the shadow inside the mask, which cuts at the view's bounds.
        .padding(.vertical, WallReaderFilmstrip.shadowRoom)
        // One shadow for the strip, which lifts the thumbnails off a page of their own colour.
        .shadow(color: .black.opacity(0.5), radius: 5, y: 2)
        .mask { LinearGradient(gradient: Self.fade, startPoint: .leading, endPoint: .trailing) }
    }
}
