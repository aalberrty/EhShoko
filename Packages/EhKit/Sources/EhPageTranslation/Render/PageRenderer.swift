import CoreGraphics
import CoreText
import EhModels
import Foundation

/// The drawing half of page translation: erases the original text of each translated block
/// and letters the translation in its place.
///
/// The result is patches, not a page: small bitmaps that the reader lays over the original
/// image. Everything is found from the page's own pixels, so a page can be drawn again from
/// its stored text with no detector, reader or translator.
public struct PageRenderer: Sendable {
    public var fonts: FontLibrary
    var analyzer = PageAnalyzer()
    var typesetter = Typesetter()

    public init(fonts: FontLibrary = .bundled) {
        self.fonts = fonts
    }

    /// Draws the blocks of `blocks` that have a translation. Sound effects and blocks without
    /// one are left as they are.
    ///
    /// Text on artwork is repainted by `inpainter` when one is given and filled smoothly
    /// otherwise; text in balloons is always filled. Runs on the global executor, checks for
    /// cancellation between blocks, and throws only `CancellationError`.
    @concurrent
    public func render(
        page: PageBitmap, blocks: [TextBlock], inpainter: (any Inpainter)? = nil
    ) async throws -> PageRender {
        let clock = ContinuousClock()
        var timings = RenderTimings()
        var start = clock.now
        let analysis = try analyzer.analyze(page: page, blocks: blocks)
        timings.analysis = clock.now - start
        let boxes = blocks.map { PixelRect(covering: $0.box) }
        var rendered: [RenderedBlock] = []
        var failedRepaints = 0
        for block in analysis.blocks {
            try Task.checkCancellation()
            var canvas = PixelWindow(page: page, rect: canvasRect(for: block))
            var isRepainted = false
            start = clock.now
            if let interior = block.interior {
                Eraser.pushPull(&canvas, mask: block.erase, known: interior)
                timings.filling += clock.now - start
            } else if let inpainter {
                do {
                    try await TiledRepaint.repaint(&canvas, page: page, mask: block.erase, with: inpainter)
                    isRepainted = true
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    // A model that fails must not cost the page its translation.
                    failedRepaints += 1
                    Eraser.pushPull(&canvas, mask: block.erase)
                }
                timings.repainting += clock.now - start
            } else {
                Eraser.pushPull(&canvas, mask: block.erase)
                timings.filling += clock.now - start
            }
            start = clock.now
            let neighbours = boxes.enumerated().filter { $0.offset != block.index }.map(\.element)
            let lettering = letter(block, text: blocks[block.index].translation, canvas: canvas, neighbours: neighbours)
            timings.fitting += clock.now - start
            start = clock.now
            let path = typesetter.path(for: lettering.layout, font: lettering.font, pageHeight: Double(page.height))
            let patch = PatchBuilder.patch(canvas: canvas, erase: block.erase, lettering: path, paint: lettering.paint, page: page)
            timings.drawing += clock.now - start
            guard let patch else { continue }
            rendered.append(RenderedBlock(
                index: block.index, kind: block.kind, patch: patch, isInBalloon: block.isInBalloon,
                isRepainted: isRepainted, isVertical: lettering.layout.isVertical,
                measuredFontSize: block.style.fontSize, fontSize: lettering.layout.fontSize,
                lines: lettering.layout.lineTexts, overflows: lettering.layout.overflows
            ))
        }
        return PageRender(blocks: rendered, timings: timings, failedRepaints: failedRepaints)
    }

    /// The pixels a block's erasing and lettering read: its erase mask and the area its
    /// lettering may use, with room for the fill to look at what lies around the mask.
    private func canvasRect(for block: BlockAnalysis) -> PixelRect {
        let area = block.interior?.rect ?? LayoutAreas.artworkRect(for: block)
        return block.erase.rect.union(area).insetBy(-12, -12)
    }

    private struct Lettering {
        var layout: TextLayout
        var font: CTFont
        var paint: PatchBuilder.Paint
    }

    /// Fits a block's translation to its area and picks the font and paint it is drawn with.
    private func letter(_ block: BlockAnalysis, text: String, canvas: PixelWindow, neighbours: [PixelRect]) -> Lettering {
        let style = block.style
        let face = fonts.face(style.face)
        // A shout stays a shout even where its strokes were measured a little thin.
        let weight = style.face == .bold ? max(style.weight, 0.13) : style.weight
        let fontAt: (Double) -> CTFont = { face.matching(weight: weight, size: $0).font }
        let area = block.isInBalloon
            ? LayoutAreas.balloon(for: block, neighbours: neighbours)
            : LayoutAreas.artwork(for: block, canvas: canvas)
        // In a balloon the text may grow a little; over artwork it never covers more than the
        // old text did.
        let growth = block.isInBalloon ? typesetter.maximumGrowth : 1.0
        var layout = typesetter.fit(
            text, area: area, style: style, isVertical: style.isVertical, maximumGrowth: growth, fontAt: fontAt
        )
        if style.isVertical {
            // Rows only where the space clearly lies on its side and columns would be much
            // smaller.
            let rect = area.mask.rect
            let cramped = layout.overflows || layout.fontSize < 0.75 * style.fontSize
            if Double(rect.width) > 1.8 * Double(rect.height), cramped {
                let rows = typesetter.fit(
                    text, area: area, style: style, isVertical: false, maximumGrowth: growth, fontAt: fontAt
                )
                if !rows.overflows, rows.fontSize > layout.fontSize * 1.15 { layout = rows }
            }
        }
        let match = face.matching(weight: weight, size: layout.fontSize)
        let scale = layout.fontSize / max(1, style.fontSize)
        let paint = PatchBuilder.Paint(
            ink: style.ink, outline: style.outline, outlineWidth: style.outlineWidth * scale,
            extraStroke: match.extraStroke
        )
        return Lettering(layout: layout, font: match.font, paint: paint)
    }
}
