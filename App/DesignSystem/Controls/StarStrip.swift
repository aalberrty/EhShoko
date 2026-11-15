import SwiftUI
import UIKit

/// Five stars for each rating in half stars (0 to 10), as one template image each: one image
/// in a row or a cell instead of five symbols (`spikes/S1.md`: about a tenth of Shelf's row).
/// Tinted where it is drawn.
///
/// The eleven strips of one symbol configuration are drawn once and kept: a few kilobytes per
/// text size and scale the app shows stars at.
enum StarStrip {
    /// What a configuration is made of: the font's name (or the weight's) and size, and the
    /// scale.
    private struct Key: Hashable {
        let face: String
        let pointSize: CGFloat
        let scale: Int
    }

    private static var cache: [Key: [Image]] = [:]

    /// The strips for stars of `pointSize` points, regular weight: what Shelf's rows draw.
    static func strips(pointSize: CGFloat) -> [Image] {
        strips(
            UIImage.SymbolConfiguration(pointSize: pointSize, weight: .regular),
            key: Key(face: "regular", pointSize: pointSize, scale: UIImage.SymbolScale.default.rawValue)
        )
    }

    /// The strips for stars as the symbols would be drawn in `font` at `scale`.
    static func strips(font: UIFont, scale: UIImage.SymbolScale) -> [Image] {
        strips(
            UIImage.SymbolConfiguration(font: font, scale: scale),
            key: Key(face: font.fontName, pointSize: font.pointSize, scale: scale.rawValue)
        )
    }

    /// The strip for `halfStars` (clamped to 0...10) among `strips`.
    static func strip(_ halfStars: Int, of strips: [Image]) -> Image {
        strips[min(max(halfStars, 0), strips.count - 1)]
    }

    private static func strips(_ configuration: UIImage.SymbolConfiguration, key: Key) -> [Image] {
        if let strips = cache[key] { return strips }
        let strips = draw(configuration)
        cache[key] = strips
        return strips
    }

    private static func draw(_ configuration: UIImage.SymbolConfiguration) -> [Image] {
        let symbols = ["star", "star.leadinghalf.filled", "star.fill"].map {
            UIImage(systemName: $0, withConfiguration: configuration)
        }
        let width = symbols.compactMap { $0?.size.width }.max() ?? 1
        let height = symbols.compactMap { $0?.size.height }.max() ?? 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width * 5, height: height))
        return (0...10).map { half in
            let strip = renderer.image { _ in
                for index in 0..<5 {
                    // 2 for a full star, 1 for half, 0 for none.
                    let fill = min(max(half - index * 2, 0), 2)
                    guard let symbol = symbols[fill] else { continue }
                    let origin = CGPoint(
                        x: CGFloat(index) * width + (width - symbol.size.width) / 2,
                        y: (height - symbol.size.height) / 2
                    )
                    symbol.withTintColor(.black).draw(at: origin)
                }
            }
            return Image(uiImage: strip.withRenderingMode(.alwaysTemplate))
        }
    }
}
