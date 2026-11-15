import EhCore
import Kingfisher
import SwiftUI

/// What the card stands on (`wall.md` section 4): the ground, and over its top a still mesh of
/// the cover's colours that fades into it. Until the colours are known it is the ground alone.
/// Content, not glass, and it never moves: the panel scrolls over it.
struct WallGalleryBackdrop: View, Equatable {
    let palette: CoverPalette?
    /// How far down the colours reach.
    let height: CGFloat
    let ground: Color

    var body: some View {
        ground
            .overlay(alignment: .top) {
                if let palette {
                    MeshGradient(width: 3, height: 3, points: Self.points, colors: Self.colors(of: palette))
                        .frame(height: height)
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.35), value: palette)
            .ignoresSafeArea()
            .accessibilityHidden(true)
    }

    /// Three rows: the colours at the top edge, again thinner across the middle, and gone at
    /// the bottom, so the mesh ends in the ground without an edge.
    private static let points: [SIMD2<Float>] = [
        [0, 0], [0.5, 0], [1, 0],
        [0, 0.55], [0.5, 0.5], [1, 0.55],
        [0, 1], [0.5, 1], [1, 1],
    ]

    /// The cover's most common colour runs down the middle with the others at the corners
    /// (`CoverPalette` has five). The bottom row is the middle row's colours at no opacity,
    /// not `clear`, which is black and would darken the fade.
    private static func colors(of palette: CoverPalette) -> [Color] {
        let colors = palette.colors
        guard colors.count >= CoverPaletteExtractor.colorCount else { return Array(repeating: .clear, count: 9) }
        let top = [colors[1], colors[0], colors[2]]
        let middle = [colors[3], colors[0], colors[4]]
        return top.map { color($0, opacity: 0.62) }
            + middle.map { color($0, opacity: 0.44) }
            + middle.map { color($0, opacity: 0) }
    }

    private static func color(_ rgb: CoverPalette.RGB, opacity: Double) -> Color {
        Color(.sRGB, red: rgb.red, green: rgb.green, blue: rgb.blue, opacity: opacity)
    }
}

/// The cover on the backdrop, with a shadow under it. The bitmap is the one the list decoded,
/// so the zoom from the list's cover lands on it.
struct WallGalleryCover: View {
    let url: URL?
    let size: CGSize

    @Environment(\.look) private var look

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        CoverImage(url: url, size: size, cornerRadius: 12)
            // The shadow is cast by a plain shape behind the image, which Core Animation draws
            // from its path, not from the image's pixels.
            .background {
                shape
                    .fill(look.background)
                    .shadow(color: .black.opacity(0.4), radius: 22, y: 16)
            }
            .overlay { shape.strokeBorder(.gray.opacity(0.35), lineWidth: 0.5) }
    }
}

/// Takes a cover's palette from the bitmap `CoverImage` shows, away from the main actor.
nonisolated enum WallCoverPalette {
    /// The palette of the cover at `url`. The options are `CoverImage`'s, so this finds the
    /// cover's one decoded bitmap in the cache, or joins the load the cover view started:
    /// nothing is decoded a second time.
    static func load(_ url: URL) async -> CoverPalette? {
        let options: KingfisherOptionsInfo = [.processor(CoverProcessor.shared), .cacheOriginalImage, .cacheMemoryOnly]
        guard let result = try? await KingfisherManager.shared.retrieveImage(with: url, options: options),
              !Task.isCancelled,
              let image = result.image.cgImage
        else { return nil }
        return await extract(image)
    }

    @concurrent
    private static func extract(_ image: CGImage) async -> CoverPalette? {
        CoverPaletteExtractor.palette(of: image)
    }
}
