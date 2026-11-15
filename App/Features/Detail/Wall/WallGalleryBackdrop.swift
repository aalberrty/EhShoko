import EhCore
import Kingfisher
import SwiftUI

/// What stands behind the panel of Wall's gallery page: a still mesh of the cover's own
/// colours across the top, fading into the ground, and the cover on it. Neither moves; the
/// panel scrolls over them. Until the colours are known there is only the ground.
///
/// The palette is this view's own state, so it goes with the page. It is worked out once,
/// off the main actor, from the bitmap `CoverImage` decoded: the same cache entry, so a
/// cover opened from a list is not decoded again for it.
struct WallGalleryBackdrop: View {
    let coverURL: URL?
    let metrics: WallGalleryMetrics

    @State private var palette: CoverPalette?
    @Environment(\.look) private var look

    private static let coverCornerRadius: CGFloat = 12

    var body: some View {
        ZStack(alignment: .top) {
            if let palette {
                WallBackdropMesh(palette: palette)
                    .transition(.opacity)
            }
            cover
                .padding(.top, metrics.coverTop)
        }
        .frame(maxWidth: .infinity)
        .frame(height: metrics.backdropHeight, alignment: .top)
        .ignoresSafeArea(.container, edges: .top)
        .animation(.easeOut(duration: 0.35), value: palette)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task(id: coverURL) {
            // Once: coming back from a child screen starts this task again.
            guard palette == nil, let coverURL else { return }
            palette = await WallCoverPalette.extract(from: coverURL)
        }
    }

    private var cover: some View {
        let shape = RoundedRectangle(cornerRadius: Self.coverCornerRadius, style: .continuous)
        return CoverImage(url: coverURL, size: metrics.coverSize, cornerRadius: Self.coverCornerRadius)
            // The shadow is cast by a plain shape behind the cover, so it is drawn from a
            // path and not from the image's pixels. It is not in scrolling content: the cover
            // stands still under the panel.
            .background {
                shape
                    .fill(look.surface)
                    .shadow(color: .black.opacity(0.4), radius: 22, y: 18)
            }
            .overlay { shape.strokeBorder(look.separator, lineWidth: 0.5) }
    }
}

/// The mesh: the palette's colours across the top, thinner in the middle and gone at the
/// bottom edge, where the ground shows. Its bottom row repeats the middle row's hues at no
/// opacity, so the fade passes through no grey.
private struct WallBackdropMesh: View, Equatable {
    let palette: CoverPalette

    var body: some View {
        MeshGradient(
            width: 3, height: 3,
            points: [
                [0, 0], [0.5, 0], [1, 0],
                [0, 0.55], [0.5, 0.5], [1, 0.55],
                [0, 1], [0.5, 1], [1, 1],
            ],
            colors: [
                color(1, 0.62), color(0, 0.62), color(2, 0.62),
                color(3, 0.42), color(0, 0.38), color(4, 0.42),
                color(3, 0), color(0, 0), color(4, 0),
            ]
        )
    }

    /// The palette always has its five colours; a shorter one repeats its last.
    private func color(_ index: Int, _ opacity: Double) -> Color {
        guard let rgb = palette.colors.indices.contains(index) ? palette.colors[index] : palette.colors.last else {
            return .clear
        }
        return Color(.sRGB, red: rgb.red, green: rgb.green, blue: rgb.blue, opacity: opacity)
    }
}

/// The cover's palette, from the decoded cover in the image cache.
nonisolated enum WallCoverPalette {
    /// Runs off the main actor: the cache lookup (or the download, shared with the cover on
    /// screen, when the cover was never shown) and the count over the bitmap's pixels.
    @concurrent
    static func extract(from url: URL) async -> CoverPalette? {
        // `CoverImage`'s own options, so this asks for the entry the cover is drawn from.
        let options: KingfisherOptionsInfo = [.processor(CoverProcessor.shared), .cacheOriginalImage, .cacheMemoryOnly]
        guard let result = try? await KingfisherManager.shared.retrieveImage(with: url, options: options),
              let image = result.image.cgImage
        else { return nil }
        return CoverPaletteExtractor.palette(of: image)
    }
}
