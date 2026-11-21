import CoreGraphics
import EhModels
import Foundation

/// Stages 5 and 6 for one page: its stored text drawn into patches.
///
/// Drawing always starts from the page's text as it is stored (`PageTranslation`: boxes as
/// fractions, no masks), also the first time, right after the text was made. So a page drawn
/// again later from the database, with no detector, reader or translator loaded, is drawn
/// from exactly what the first drawing had and comes out the same.
public enum PageDrawer {
    /// The blocks of a stored page in pixels of `page`, as the renderer takes them. A balloon
    /// carries its box alone: the renderer finds its interior from the page's pixels.
    public static func blocks(of translation: PageTranslation, on page: PageBitmap) -> [TextBlock] {
        let width = CGFloat(page.width), height = CGFloat(page.height)
        func rect(_ fraction: FractionalRect) -> CGRect {
            CGRect(
                x: CGFloat(fraction.x) * width, y: CGFloat(fraction.y) * height,
                width: CGFloat(fraction.width) * width, height: CGFloat(fraction.height) * height
            )
        }
        return translation.regions.map { region in
            TextBlock(
                box: rect(region.box), kind: region.kind, isVertical: region.isVertical, score: Float(region.score),
                balloon: region.balloonBox.map { Balloon(box: rect($0)) }, source: region.source,
                translation: region.translation
            )
        }
    }

    /// Erases and letters the translated blocks of `translation` on `page`.
    ///
    /// Text on artwork is repainted by `inpainter` when one is given and filled otherwise.
    /// Runs off the caller's actor, looks for cancellation between blocks and between tiles,
    /// and throws only `CancellationError`.
    public static func draw(
        _ translation: PageTranslation, on page: PageBitmap, inpainter: (any Inpainter)? = nil,
        renderer: PageRenderer = PageRenderer()
    ) async throws -> PageDrawing {
        let render = try await renderer.render(
            page: page, blocks: blocks(of: translation, on: page), inpainter: inpainter
        )
        return PageDrawing(render)
    }
}

/// A page's patches with what drawing them took.
public struct PageDrawing: Sendable, Equatable {
    /// One patch for each block that was drawn, in the order of the page's regions. Patches
    /// can overlap (two blocks in one balloon), so the order is kept when they are shown.
    public var patches: [Patch]
    public var timings: PageDrawingTimings
    /// Blocks on artwork that the repaint model repainted.
    public var repaintedBlocks: Int
    /// Blocks on artwork that the repaint model failed on and the fill erased instead.
    public var failedRepaints: Int
    /// Blocks whose translation did not fit its area at the smallest size.
    public var overflowingBlocks: Int

    public init(
        patches: [Patch], timings: PageDrawingTimings = PageDrawingTimings(), repaintedBlocks: Int = 0,
        failedRepaints: Int = 0, overflowingBlocks: Int = 0
    ) {
        self.patches = patches
        self.timings = timings
        self.repaintedBlocks = repaintedBlocks
        self.failedRepaints = failedRepaints
        self.overflowingBlocks = overflowingBlocks
    }

    init(_ render: PageRender) {
        self.init(
            patches: render.patches, timings: PageDrawingTimings(render.timings),
            repaintedBlocks: render.blocks.filter(\.isRepainted).count, failedRepaints: render.failedRepaints,
            overflowingBlocks: render.blocks.filter(\.overflows).count
        )
    }
}

/// The time each step of drawing a page took, summed over its blocks.
public struct PageDrawingTimings: Sendable, Equatable {
    /// Finding balloons, ink, columns and style.
    public var analysis: Duration
    /// The smooth fill.
    public var filling: Duration
    /// The repaint model, tiles and pasting included.
    public var repainting: Duration
    /// Fitting the translation to its area.
    public var fitting: Duration
    /// Drawing the glyphs and making the patches.
    public var drawing: Duration

    public init(
        analysis: Duration = .zero, filling: Duration = .zero, repainting: Duration = .zero,
        fitting: Duration = .zero, drawing: Duration = .zero
    ) {
        self.analysis = analysis
        self.filling = filling
        self.repainting = repainting
        self.fitting = fitting
        self.drawing = drawing
    }

    init(_ timings: RenderTimings) {
        self.init(
            analysis: timings.analysis, filling: timings.filling, repainting: timings.repainting,
            fitting: timings.fitting, drawing: timings.drawing
        )
    }

    public var total: Duration { analysis + filling + repainting + fitting + drawing }
}
