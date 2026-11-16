import CoreGraphics
import EhModels
import Foundation

/// A page's translation, drawn: one patch for each block that was erased and lettered.
public struct PageRender: Sendable {
    /// The blocks that were drawn, in the order they were given.
    public var blocks: [RenderedBlock]
    /// How long each step took.
    public var timings: RenderTimings
    /// Blocks on artwork that the repaint model failed on and the fill erased instead.
    public var failedRepaints: Int

    public var patches: [Patch] { blocks.map(\.patch) }

    /// The page with its patches laid over it, as the reader shows it: for checks and
    /// measurements, since the reader itself keeps the page and the patches apart.
    public func composited(over page: PageBitmap) -> CGImage? {
        PatchBuilder.composite(patches, over: page)
    }
}

/// One block as it was drawn.
public struct RenderedBlock: Sendable {
    /// The block's place in the list that was given to the renderer.
    public var index: Int
    /// What the block turned out to be on the page: `.dialogue` in a balloon, `.caption` in a
    /// rectangular box, otherwise the kind it came with.
    public var kind: RegionKind
    public var patch: Patch
    /// Whether the page's pixels showed a closed balloon or box around the text.
    public var isInBalloon: Bool
    /// Whether the artwork behind the text was repainted by the model rather than filled.
    public var isRepainted: Bool
    public var isVertical: Bool
    /// The size of the original lettering, in pixels of the page bitmap.
    public var measuredFontSize: Double
    /// The size the translation is set at.
    public var fontSize: Double
    /// The translation as it was broken into columns or rows.
    public var lines: [String]
    /// The translation did not fit at the smallest size and runs over its area.
    public var overflows: Bool
}

/// The time each step of drawing a page took, summed over its blocks.
public struct RenderTimings: Sendable {
    /// Finding balloons, ink, columns and style.
    public var analysis: Duration = .zero
    /// The smooth fill.
    public var filling: Duration = .zero
    /// The repaint model, tiles and pasting included.
    public var repainting: Duration = .zero
    /// Fitting the translation to its area.
    public var fitting: Duration = .zero
    /// Drawing the glyphs and making the patches.
    public var drawing: Duration = .zero

    public var total: Duration { analysis + filling + repainting + fitting + drawing }
}
