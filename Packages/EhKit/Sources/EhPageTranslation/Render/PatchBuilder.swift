import CoreGraphics
import Foundation
import ImageIO

/// Makes a block's patch: its erased background and its new lettering on a transparent
/// ground.
enum PatchBuilder {
    /// What the lettering is painted with.
    struct Paint {
        var ink: PixelColor
        var outline: PixelColor?
        var outlineWidth: Double
        var extraStroke: Double
    }

    /// - Parameters:
    ///   - canvas: the block's pixels after erasing; it must hold `erase`.
    ///   - erase: the pixels that were erased. They are opaque in the patch.
    ///   - lettering: the glyph outlines in Core Graphics coordinates of the page (y up), or
    ///     `nil` to make a patch that only erases.
    /// - Returns: `nil` when nothing was erased or drawn on the page.
    static func patch(
        canvas: PixelWindow, erase: RegionMask, lettering: CGPath?, paint: Paint, page: PageBitmap
    ) -> Patch? {
        var rect = erase.rect
        if let lettering, !lettering.isEmpty {
            let bounds = lettering.boundingBoxOfPath
            let reach = Painter.reach(outlineWidth: paint.outlineWidth, extraStroke: paint.extraStroke)
            let onPage = CGRect(
                x: bounds.minX, y: CGFloat(page.height) - bounds.maxY, width: bounds.width, height: bounds.height
            ).insetBy(dx: -reach, dy: -reach)
            rect = rect.union(PixelRect(covering: onPage))
        }
        rect = rect.clamped(width: page.width, height: page.height)
        guard !rect.isEmpty else { return nil }
        var pixels = Data(count: rect.area * 4)
        let drawn = pixels.withUnsafeMutableBytes { raw -> Bool in
            guard let base = raw.baseAddress else { return false }
            copyErased(from: canvas, erase: erase, to: base.assumingMemoryBound(to: UInt8.self), rect: rect)
            guard let lettering, !lettering.isEmpty else { return true }
            guard let context = CGContext(
                data: base, width: rect.width, height: rect.height, bitsPerComponent: 8, bytesPerRow: rect.width * 4,
                space: page.colorSpace, bitmapInfo: Patch.bitmapInfo.rawValue
            ) else { return false }
            // The outlines are in page coordinates with y up; the patch's lower left corner
            // is the page's (x0, height - y1).
            context.translateBy(x: -CGFloat(rect.x0), y: -CGFloat(page.height - rect.y1))
            Painter.draw(
                lettering, in: context, colorSpace: page.colorSpace, ink: paint.ink, outline: paint.outline,
                outlineWidth: paint.outlineWidth, extraStroke: paint.extraStroke
            )
            return true
        }
        return drawn ? Patch(rect: rect, pixels: pixels) : nil
    }

    /// Writes the erased pixels, opaque, into a patch buffer that is otherwise transparent.
    private static func copyErased(from canvas: PixelWindow, erase: RegionMask, to pixels: UnsafeMutablePointer<UInt8>, rect: PixelRect) {
        let shared = erase.rect.intersection(rect).intersection(canvas.rect)
        guard !shared.isEmpty else { return }
        for y in shared.y0..<shared.y1 {
            for x in shared.x0..<shared.x1 where erase.contains(x, y) {
                let color = canvas.color(canvas.index(x, y))
                let offset = ((y - rect.y0) * rect.width + x - rect.x0) * 4
                pixels[offset] = color.red
                pixels[offset + 1] = color.green
                pixels[offset + 2] = color.blue
                pixels[offset + 3] = 255
            }
        }
    }
}

extension PatchBuilder {
    /// `image` as a PNG file with its colour space embedded: for pictures of whole pages made
    /// by checks. A page's patches are stored by the patch file, not by this.
    static func pngData(of image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }

    /// The page with `patches` laid over it, as the reader shows a translated page.
    static func composite(_ patches: [Patch], over page: PageBitmap) -> CGImage? {
        guard let context = CGContext(
            data: nil, width: page.width, height: page.height, bitsPerComponent: 8, bytesPerRow: page.width * 4,
            space: page.colorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .none
        context.draw(page.cgImage, in: CGRect(x: 0, y: 0, width: page.width, height: page.height))
        for patch in patches {
            guard let image = patch.makeImage(colorSpace: page.colorSpace) else { continue }
            let rect = patch.rect
            context.draw(image, in: CGRect(x: rect.x0, y: page.height - rect.y1, width: rect.width, height: rect.height))
        }
        return context.makeImage()
    }
}
