import CoreGraphics
import CoreText
@testable import EhPageTranslation
import EhModels
import Foundation

/// Lettered pages made by the tests: balloons with vertical Japanese on plain paper, on a
/// gradient and on a texture. The helper also says where each balloon's inside and each
/// glyph's pixels are, so a test can compare what drawing found with what was drawn.
extension SyntheticImages {
    /// What the page is drawn on.
    enum Ground: Sendable {
        case white
        /// Light grey fading to mid grey.
        case gradient
        /// Screentone dots and crossing lines.
        case texture
    }

    enum BalloonShape: Sendable {
        case ellipse
        /// A caption box.
        case box
        /// No balloon: the text stands on the ground.
        case none
    }

    /// One block of vertical text and the balloon around it.
    struct Lettering: Sendable {
        /// The columns from right to left.
        var columns: [String]
        var fontSize: CGFloat
        /// The centre of the text and of its balloon.
        var centre: CGPoint
        var shape: BalloonShape = .ellipse
        var balloonSize: CGSize = CGSize(width: 150, height: 220)
        /// The distance between columns, in ems.
        var linePitch: CGFloat = 1.3
        var fontName = "HiraginoSans-W4"
        /// Small kana set beside each column, by column; an empty string for none.
        var ruby: [String] = []
        /// The balloon's fill, from this grey at the top to `balloonGrayBottom` at the bottom.
        var balloonGray: CGFloat = 1
        var balloonGrayBottom: CGFloat?
        var inkGray: CGFloat = 0
        /// A band of this grey and width drawn round the glyphs, as outlined lettering has.
        var bandGray: CGFloat?
        var bandWidth: CGFloat = 0
        var translation = "这是一段译文。"
        /// Whether the block carries the detector's balloon, and its mask as well.
        var hint: Hint = .box

        enum Hint: Sendable { case none, box, mask }

        var balloonRect: CGRect {
            CGRect(x: centre.x - balloonSize.width / 2, y: centre.y - balloonSize.height / 2,
                   width: balloonSize.width, height: balloonSize.height)
        }

        /// A box that holds the text however it is set.
        var textBounds: CGRect {
            let halfWidth = (CGFloat(columns.count) * linePitch / 2 + 1.5) * fontSize
            let halfHeight = (CGFloat(columns.map(\.count).max() ?? 0) / 2 + 1) * fontSize
            return CGRect(x: centre.x - halfWidth, y: centre.y - halfHeight, width: halfWidth * 2, height: halfHeight * 2)
        }
    }

    struct LetteredPage: Sendable {
        var bitmap: PageBitmap
        /// One block for each lettering that has text, in order.
        var blocks: [TextBlock]
        /// The pixels of each block's glyphs, ruby included.
        var glyphs: [RegionMask]
        /// The inside of each balloon, within its outline; `nil` for text without one.
        var interiors: [RegionMask?]

        var image: CGImage { bitmap.cgImage }
    }

    static let outlineWidth: CGFloat = 3

    /// Draws the page straight into a page bitmap, with no file in between, and each mask in
    /// a small bitmap of its own: these pages are made many times in a test run.
    static func letteredPage(
        width: Int, height: Int, ground: Ground = .white, letterings: [Lettering]
    ) throws -> LetteredPage {
        var pixels = Data(count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(
                data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: sRGB, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            ) else { return false }
            context.translateBy(x: 0, y: CGFloat(height))
            context.scaleBy(x: 1, y: -1)
            draw(ground, in: context, width: width, height: height)
            for lettering in letterings {
                drawBalloon(lettering, in: context)
                drawText(lettering, in: context, gray: lettering.inkGray)
            }
            return true
        }
        guard drawn else { throw SyntheticPageError.drawing }
        let bitmap = try PageBitmap(
            width: width, height: height, originalWidth: width, originalHeight: height, pixels: pixels, colorSpace: sRGB
        )
        let page = PixelRect(x: 0, y: 0, width: width, height: height)
        var blocks: [TextBlock] = [], glyphs: [RegionMask] = [], interiors: [RegionMask?] = []
        // A lettering without text draws its balloon alone and gives no block.
        for lettering in letterings where !lettering.columns.isEmpty {
            let area = PixelRect(covering: lettering.balloonRect.union(lettering.textBounds).insetBy(dx: -6, dy: -6))
                .intersection(page)
            let glyphMask = try mask(in: area) { drawText(lettering, in: $0, gray: 0, band: false) }
            let interior = lettering.shape == .none ? nil : try mask(in: area) { context in
                context.setFillColor(gray: 0, alpha: 1)
                addShape(lettering, to: context, inset: outlineWidth / 2 + 1)
                context.fillPath()
            }
            var balloon: Balloon?
            if lettering.shape != .none, lettering.hint != .none {
                balloon = Balloon(box: lettering.balloonRect, mask: lettering.hint == .mask ? interior : nil)
            }
            blocks.append(TextBlock(
                box: glyphMask.rect.insetBy(-1, -1).cgRect, kind: lettering.shape == .none ? .aside : .dialogue,
                isVertical: true, score: 0.9, balloon: balloon, source: lettering.columns.joined(),
                translation: lettering.translation
            ))
            glyphs.append(glyphMask)
            interiors.append(interior)
        }
        return LetteredPage(bitmap: bitmap, blocks: blocks, glyphs: glyphs, interiors: interiors)
    }

    enum SyntheticPageError: Error { case drawing }

    // MARK: Drawing

    private static func draw(_ ground: Ground, in context: CGContext, width: Int, height: Int) {
        let w = CGFloat(width), h = CGFloat(height)
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: w, height: h))
        switch ground {
        case .white:
            break
        case .gradient:
            let colors = [CGColor(gray: 0.92, alpha: 1), CGColor(gray: 0.45, alpha: 1)] as CFArray
            if let gradient = CGGradient(colorsSpace: sRGB, colors: colors, locations: nil) {
                context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: w, y: h), options: [])
            }
        case .texture:
            context.setFillColor(gray: 0.15, alpha: 1)
            for y in stride(from: CGFloat(3), to: h, by: 7) {
                for x in stride(from: CGFloat(3), to: w, by: 7) {
                    context.fillEllipse(in: CGRect(x: x, y: y, width: 3, height: 3))
                }
            }
            context.setStrokeColor(gray: 0.1, alpha: 1)
            context.setLineWidth(2)
            for offset in stride(from: -h, to: w, by: 90) {
                context.move(to: CGPoint(x: offset, y: 0))
                context.addLine(to: CGPoint(x: offset + h, y: h))
            }
            context.strokePath()
        }
    }

    private static func addShape(_ lettering: Lettering, to context: CGContext, inset: CGFloat) {
        let rect = lettering.balloonRect.insetBy(dx: inset, dy: inset)
        switch lettering.shape {
        case .ellipse: context.addEllipse(in: rect)
        case .box: context.addRect(rect)
        case .none: break
        }
    }

    private static func drawBalloon(_ lettering: Lettering, in context: CGContext) {
        guard lettering.shape != .none else { return }
        context.saveGState()
        addShape(lettering, to: context, inset: 0)
        context.clip()
        let rect = lettering.balloonRect
        let top = CGColor(gray: lettering.balloonGray, alpha: 1)
        let bottom = CGColor(gray: lettering.balloonGrayBottom ?? lettering.balloonGray, alpha: 1)
        if let gradient = CGGradient(colorsSpace: sRGB, colors: [top, bottom] as CFArray, locations: nil) {
            context.drawLinearGradient(
                gradient, start: CGPoint(x: rect.midX, y: rect.minY), end: CGPoint(x: rect.midX, y: rect.maxY),
                options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
            )
        }
        context.restoreGState()
        context.setStrokeColor(gray: 0, alpha: 1)
        context.setLineWidth(outlineWidth)
        addShape(lettering, to: context, inset: 0)
        context.strokePath()
    }

    /// Sets the columns with Core Text, one character to a square, top-aligned, and the ruby
    /// at half size to the right of its column.
    private static func drawText(_ lettering: Lettering, in context: CGContext, gray: CGFloat, band: Bool = true) {
        let size = lettering.fontSize, pitch = size * lettering.linePitch
        let font = CTFontCreateWithName(lettering.fontName as CFString, size, nil)
        let small = CTFontCreateWithName(lettering.fontName as CFString, size / 2, nil)
        let longest = lettering.columns.map(\.count).max() ?? 0
        let top = lettering.centre.y - CGFloat(longest) * size / 2
        let count = lettering.columns.count
        // The helper's contexts have their origin at the top left, so glyphs are flipped back.
        context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        // The band first, under every glyph, then the glyphs.
        var passes: [(mode: CGTextDrawingMode, gray: CGFloat)] = [(.fill, gray)]
        if band, let grey = lettering.bandGray, lettering.bandWidth > 0 { passes.insert((.fillStroke, grey), at: 0) }
        for pass in passes {
            context.setTextDrawingMode(pass.mode)
            context.setFillColor(gray: pass.gray, alpha: 1)
            context.setStrokeColor(gray: pass.gray, alpha: 1)
            context.setLineWidth(lettering.bandWidth * 2)
            context.setLineJoin(.round)
            for (index, column) in lettering.columns.enumerated() {
                let x = lettering.centre.x + (CGFloat(count - 1) / 2 - CGFloat(index)) * pitch
                draw(column, font: font, size: size, centreX: x, top: top, in: context)
                if index < lettering.ruby.count, !lettering.ruby[index].isEmpty {
                    draw(lettering.ruby[index], font: small, size: size / 2, centreX: x + size * 0.78, top: top, in: context)
                }
            }
        }
        context.setTextDrawingMode(.fill)
    }

    private static func draw(_ text: String, font: CTFont, size: CGFloat, centreX: CGFloat, top: CGFloat, in context: CGContext) {
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true
        ]
        for (row, character) in text.enumerated() {
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: String(character), attributes: attributes))
            let width = CTLineGetTypographicBounds(line, nil, nil, nil)
            context.textPosition = CGPoint(x: centreX - width / 2, y: top + CGFloat(row) * size + size * 0.88)
            CTLineDraw(line, context)
        }
    }

    /// The pixels `draw` paints dark inside `area` of the page, as a mask cut to their bounds.
    private static func mask(in area: PixelRect, draw: (CGContext) -> Void) throws -> RegionMask {
        let width = area.width, height = area.height
        var grey = [UInt8](repeating: 255, count: width * height)
        let drawn = grey.withUnsafeMutableBytes { raw -> Bool in
            guard width > 0, height > 0, let context = CGContext(
                data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return false }
            // Page coordinates, origin at the top left, moved to the area's corner.
            context.translateBy(x: 0, y: CGFloat(height))
            context.scaleBy(x: 1, y: -1)
            context.translateBy(x: -CGFloat(area.x0), y: -CGFloat(area.y0))
            draw(context)
            return true
        }
        guard drawn else { throw SyntheticPageError.drawing }
        var x0 = width, y0 = height, x1 = 0, y1 = 0
        for y in 0..<height {
            for x in 0..<width where grey[y * width + x] < 128 {
                x0 = min(x0, x)
                x1 = max(x1, x + 1)
                y0 = min(y0, y)
                y1 = y + 1
            }
        }
        guard x1 > x0, y1 > y0 else { throw SyntheticPageError.drawing }
        var bits = [UInt8](repeating: 0, count: (x1 - x0) * (y1 - y0))
        for y in y0..<y1 {
            for x in x0..<x1 where grey[y * width + x] < 128 { bits[(y - y0) * (x1 - x0) + x - x0] = 1 }
        }
        return RegionMask(
            rect: PixelRect(x0: area.x0 + x0, y0: area.y0 + y0, x1: area.x0 + x1, y1: area.y0 + y1), bits: bits
        )
    }
}

extension RegionMask {
    /// The share of this mask's pixels that `other` also holds.
    func share(coveredBy other: RegionMask) -> Double {
        var covered = 0, total = 0
        for y in rect.y0..<rect.y1 {
            for x in rect.x0..<rect.x1 where contains(x, y) {
                total += 1
                if other.contains(x, y) { covered += 1 }
            }
        }
        return total > 0 ? Double(covered) / Double(total) : 0
    }
}
