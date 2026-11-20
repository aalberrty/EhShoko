import CoreGraphics
import CoreText
import Foundation

extension Typesetter {
    /// The outlines of a layout's glyphs in Core Graphics coordinates (y up) of a page
    /// `pageHeight` pixels tall.
    func path(for layout: TextLayout, font: CTFont, pageHeight: Double) -> CGPath {
        let path = CGMutablePath()
        let size = layout.fontSize
        for line in layout.lines {
            var position = line.start
            for index in line.cells {
                let cell = layout.cells[index]
                if layout.isVertical {
                    addVertical(cell, font: font, fontSize: size, centreX: line.centre, top: pageHeight - position, to: path)
                } else {
                    let baseline = pageHeight - (line.centre + size * 0.38)
                    addLine(cell.text, font: font, transform: CGAffineTransform(translationX: position, y: baseline), to: path)
                }
                position += advance(cell, font: font, fontSize: size, isVertical: layout.isVertical)
            }
        }
        return path
    }

    /// Marks to turn a quarter when the face has no vertical form for them.
    static let rotatedWithoutVerticalForm: Set<Character> = Set("～—…‥（）《》〈〉「」『』【】〔〕：；-ー")
    /// Marks to move to the square's upper right when the face has no vertical form for them.
    static let shiftedWithoutVerticalForm: Set<Character> = Set("，。、．")

    private func addVertical(
        _ cell: TextCell, font: CTFont, fontSize: Double, centreX: Double, top: Double, to path: CGMutablePath
    ) {
        switch cell.form {
        case .tateChuYoko:
            let width = lineWidth(cell.text, font: font, isVertical: false)
            let scale = min(1, fontSize * 0.92 / max(1, width))
            let capHeight = CTFontGetCapHeight(font)
            let transform = CGAffineTransform(translationX: centreX - width * scale / 2, y: top - fontSize / 2 - capHeight / 2)
                .scaledBy(x: scale, y: 1)
            addLine(cell.text, font: font, transform: transform, to: path)
        case .sideways:
            let capHeight = CTFontGetCapHeight(font)
            let transform = CGAffineTransform(translationX: centreX, y: top - fontSize * 0.08)
                .rotated(by: -.pi / 2).translatedBy(x: 0, y: -capHeight / 2)
            addLine(cell.text, font: font, transform: transform, to: path)
        case .upright:
            addUpright(cell, font: font, fontSize: fontSize, centreX: centreX, top: top, to: path)
        }
    }

    private func addUpright(
        _ cell: TextCell, font: CTFont, fontSize: Double, centreX: Double, top: Double, to path: CGMutablePath
    ) {
        let vertical = line(cell.text, font, isVertical: true)
        let character = cell.text.first ?? " "
        // The face has a vertical form when vertical setting picks another glyph.
        let hasVerticalForm = Self.firstGlyph(vertical) != Self.firstGlyph(line(cell.text, font, isVertical: false))
        if !hasVerticalForm, Self.rotatedWithoutVerticalForm.contains(character) {
            // Turned a quarter and centred in its square by its own outline: where a face
            // puts a dash or an ellipsis in a row says nothing about a column.
            let glyph = CGMutablePath()
            addLine(cell.text, font: font, transform: .identity, to: glyph)
            let bounds = glyph.boundingBoxOfPath
            guard !bounds.isNull else { return }
            let transform = CGAffineTransform(translationX: centreX, y: top - fontSize / 2)
                .rotated(by: -.pi / 2).translatedBy(x: -bounds.midX, y: -bounds.midY)
            path.addPath(glyph, transform: transform)
            return
        }
        if !hasVerticalForm, Self.shiftedWithoutVerticalForm.contains(character) {
            let transform = CGAffineTransform(translationX: centreX + fontSize * 0.05, y: top - fontSize * 0.26)
            addLine(cell.text, font: font, transform: transform, to: path)
            return
        }
        var y = top
        for run in Self.runs(of: vertical) {
            let runFont = Self.font(of: run, default: font)
            let count = CTRunGetGlyphCount(run)
            var glyphs = [CGGlyph](repeating: 0, count: count)
            CTRunGetGlyphs(run, CFRange(location: 0, length: count), &glyphs)
            var translations = [CGSize](repeating: .zero, count: count)
            CTFontGetVerticalTranslationsForGlyphs(runFont, glyphs, &translations, count)
            for index in 0..<count {
                var transform = CGAffineTransform(
                    translationX: centreX + translations[index].width, y: y + translations[index].height
                )
                if let glyph = CTFontCreatePathForGlyph(runFont, glyphs[index], &transform) { path.addPath(glyph) }
                y -= fontSize
            }
        }
    }

    /// Adds `text`, set horizontally from the origin, moved by `transform`.
    private func addLine(_ text: String, font: CTFont, transform: CGAffineTransform, to path: CGMutablePath) {
        for run in Self.runs(of: line(text, font, isVertical: false)) {
            let runFont = Self.font(of: run, default: font)
            let count = CTRunGetGlyphCount(run)
            var glyphs = [CGGlyph](repeating: 0, count: count), positions = [CGPoint](repeating: .zero, count: count)
            CTRunGetGlyphs(run, CFRange(location: 0, length: count), &glyphs)
            CTRunGetPositions(run, CFRange(location: 0, length: count), &positions)
            for index in 0..<count {
                var placed = CGAffineTransform(translationX: positions[index].x, y: positions[index].y)
                    .concatenating(transform)
                if let glyph = CTFontCreatePathForGlyph(runFont, glyphs[index], &placed) { path.addPath(glyph) }
            }
        }
    }

    private static func runs(of line: CTLine) -> [CTRun] {
        let runs = CTLineGetGlyphRuns(line)
        // The array holds `CTRun` objects; Core Foundation gives them back untyped.
        return (0..<CFArrayGetCount(runs)).map { unsafeBitCast(CFArrayGetValueAtIndex(runs, $0), to: CTRun.self) }
    }

    /// The face a run was set in: `font`, or the system's substitute for a character it lacks.
    private static func font(of run: CTRun, default font: CTFont) -> CTFont {
        let attributes = CTRunGetAttributes(run) as NSDictionary
        guard let value = attributes[kCTFontAttributeName as String] else { return font }
        let object = value as CFTypeRef
        return CFGetTypeID(object) == CTFontGetTypeID() ? unsafeDowncast(object, to: CTFont.self) : font
    }

    private static func firstGlyph(_ line: CTLine) -> CGGlyph? {
        guard let run = runs(of: line).first, CTRunGetGlyphCount(run) > 0 else { return nil }
        var glyph = CGGlyph(0)
        CTRunGetGlyphs(run, CFRange(location: 0, length: 1), &glyph)
        return glyph
    }
}

/// Paints glyph outlines: the outline band first, then the fill, then an extra stroke when
/// the face cannot reach the weight on its own.
enum Painter {
    /// - Parameters:
    ///   - colorSpace: the page's, so the colours are written as they were measured.
    ///   - extraStroke: the stroke, in pixels, that makes up for a face that is too light.
    static func draw(
        _ path: CGPath, in context: CGContext, colorSpace: CGColorSpace, ink: PixelColor, outline: PixelColor?,
        outlineWidth: Double, extraStroke: Double
    ) {
        context.setShouldAntialias(true)
        context.setLineJoin(.round)
        context.setLineCap(.round)
        if let outline, outlineWidth > 0 {
            context.addPath(path)
            context.setStrokeColor(outline.cgColor(in: colorSpace))
            context.setLineWidth(2 * outlineWidth + extraStroke)
            context.strokePath()
        }
        context.addPath(path)
        context.setFillColor(ink.cgColor(in: colorSpace))
        context.fillPath()
        if extraStroke > minimumExtraStroke {
            context.addPath(path)
            context.setStrokeColor(ink.cgColor(in: colorSpace))
            context.setLineWidth(extraStroke)
            context.strokePath()
        }
    }

    /// A thinner extra stroke than this is not drawn.
    static let minimumExtraStroke = 0.15

    /// How far beyond the glyph outlines the painting reaches.
    static func reach(outlineWidth: Double, extraStroke: Double) -> Double {
        max(outlineWidth + extraStroke / 2, extraStroke / 2) + 1
    }
}
