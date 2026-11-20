import CoreGraphics

/// The pixels around one block that its analysis reads: a window of the page, the block's box
/// and the colour the text stands on.
struct BlockScene: Sendable {
    let window: PixelWindow
    /// The block's box in page pixels, cut to the page.
    let textRect: PixelRect
    /// The colour behind the text.
    let background: PixelColor
    /// Each window pixel's largest channel difference from `background`.
    let difference: [UInt8]
    let luma: [UInt8]

    /// How far beyond a balloon's box the window reaches, so an outline at the box's edge and
    /// what lies just outside it can be seen.
    static let margin = 16
    /// How far around the text a block on artwork is looked at: its ink, its style and what
    /// is erased all lie within this.
    static let artworkReach = 48

    /// The scene of `block`: the window that holds its balloon, or, with `reach`, only the
    /// text and that many pixels around it.
    init(page: PageBitmap, block: TextBlock, reach: Int? = nil) {
        let text = PixelRect(covering: block.box).clamped(width: page.width, height: page.height)
        let hint = block.balloon.map { PixelRect(covering: $0.box) }
        let rect = reach.map { text.insetBy(-$0, -$0) } ?? Self.windowRect(text: text, balloon: hint)
        let window = PixelWindow(page: page, rect: rect)
        self.window = window
        textRect = text
        let allowed = block.balloon?.mask.map { $0.plane(in: window) }
        background = Self.background(window: window, textRect: text, allowed: allowed)
        difference = window.differencePlane(from: background)
        luma = window.lumaPlane()
    }

    /// The part of `scene` inside `rect`: the measures of the lettering need only the pixels
    /// around the text, not the whole balloon.
    init(cropping scene: BlockScene, to rect: PixelRect) {
        let window = PixelWindow(cropping: scene.window, to: rect)
        self.window = window
        textRect = scene.textRect
        background = scene.background
        difference = scene.window.crop(scene.difference, to: window.rect)
        luma = scene.window.crop(scene.luma, to: window.rect)
    }

    /// The balloon's box when the detector gave one; otherwise the text's box grown by one
    /// and a half times its longer side, which holds a balloon or caption box the detector
    /// did not see: a word or two often stands in a balloon several times its size.
    static func windowRect(text: PixelRect, balloon: PixelRect?) -> PixelRect {
        if let balloon, !balloon.isEmpty {
            return balloon.union(text).insetBy(-margin, -margin)
        }
        let reach = min(240, max(64, max(text.width, text.height) * 3 / 2))
        return text.insetBy(-reach, -reach)
    }

    /// The most common colour in a ring around the text. Around it, not under it: a white
    /// outline drawn on the glyphs covers less of the ring than the balloon's own colour does.
    /// With a balloon mask, only the ring's pixels inside the balloon count.
    static func background(window: PixelWindow, textRect: PixelRect, allowed: [UInt8]?) -> PixelColor {
        let reach = min(40, max(6, min(textRect.width, textRect.height) / 3))
        let ring = window.local(textRect.insetBy(-reach, -reach)), inner = window.local(textRect)
        guard !ring.isEmpty else { return .white }
        func bin(_ color: PixelColor) -> Int {
            Int(color.red >> 4) << 8 | Int(color.green >> 4) << 4 | Int(color.blue >> 4)
        }
        func mode(includingInside: Bool) -> (bin: Int, count: Int) {
            var bins = [Int](repeating: 0, count: 4096)
            for y in ring.y0..<ring.y1 {
                for x in ring.x0..<ring.x1 where includingInside || !inner.contains(x, y) {
                    let index = y * window.width + x
                    if let allowed, allowed[index] == 0 { continue }
                    bins[bin(window.color(index))] += 1
                }
            }
            var best = 0
            for candidate in 1..<4096 where bins[candidate] > bins[best] { best = candidate }
            return (best, bins[best])
        }
        var found = mode(includingInside: false)
        // Text at the page's edge or filling its balloon leaves no ring to look at.
        if found.count < 24 { found = mode(includingInside: true) }
        guard found.count > 0 else { return .white }
        var colors = ColorHistogram()
        for y in ring.y0..<ring.y1 {
            for x in ring.x0..<ring.x1 {
                let color = window.color(y * window.width + x)
                if bin(color) == found.bin { colors.add(color) }
            }
        }
        return colors.median ?? .white
    }
}

