import EhModels
import Foundation

/// What drawing knows about one block before it erases or letters anything: where it stands,
/// which pixels are its ink and how it is lettered.
struct BlockAnalysis: Sendable {
    /// The block's place in the page's list of blocks.
    var index: Int
    /// The block's box in page pixels, cut to the page.
    var textRect: PixelRect
    /// `.dialogue` in a balloon, `.caption` in a rectangular box, otherwise what the detector
    /// said.
    var kind: RegionKind
    /// The colour behind the text.
    var background: PixelColor
    /// The inside of the balloon or caption box, the erased text included; `nil` for text on
    /// artwork.
    var interior: RegionMask?
    /// The pixels to erase.
    var erase: RegionMask
    var columns: BlockColumns
    var style: TextStyle

    var isInBalloon: Bool { interior != nil }
}

/// Analyses one block from the page's pixels: balloon, ink, columns, style, erase mask.
struct BlockAnalyzer: Sendable {
    var balloons = BalloonFinder()

    /// `nil` for a block with no box on the page or no ink in it.
    func analyze(page: PageBitmap, block: TextBlock, index: Int) -> BlockAnalysis? {
        // A block without a balloon gets a close look first. Only on a light ground can it
        // stand in a balloon the detector missed, and only then is the wide window that
        // would hold one worth making.
        var scene = BlockScene(page: page, block: block, reach: block.balloon == nil ? BlockScene.artworkReach : nil)
        if block.balloon == nil, scene.background.luma >= balloons.minimumBackgroundLuma {
            scene = BlockScene(page: page, block: block)
        }
        guard scene.textRect.width >= 2, scene.textRect.height >= 2 else { return nil }
        let cells = Columns.cellCount(of: block.source)
        let candidates = InkMask.candidates(scene: scene)
        let rough = Columns.find(ink: candidates, scene: scene, prefersVertical: block.isVertical, cellCount: cells)
        let roughGlyph = rough.glyphSize ?? Double(min(scene.textRect.width, scene.textRect.height))
        let balloon = balloons.find(scene: scene, hint: block.balloon, glyphSize: roughGlyph)
        // `strokes` is what the lettering is measured on, `ink` what is erased.
        let strokes: [UInt8], ink: [UInt8]
        if let balloon {
            ink = InkMask.insideBalloon(candidates, scene: scene, interior: balloon.filled)
            strokes = ink
        } else {
            // On artwork the first guess at the glyphs' size is not to be trusted: the shape
            // of the box and the number of characters give a sturdier one.
            let box = scene.textRect
            let fromText = Columns.expectedGlyphSize(
                extent: block.isVertical ? box.width : box.height, length: block.isVertical ? box.height : box.width,
                cellCount: cells
            )
            (strokes, ink) = InkMask.onArtwork(scene: scene, glyphSize: fromText ?? roughGlyph)
        }
        let columns = strokes == candidates
            ? rough
            : Columns.find(ink: strokes, scene: scene, prefersVertical: block.isVertical, cellCount: cells)
        guard !columns.columns.isEmpty else { return nil }

        // The style is measured on the pixels around the text alone.
        let reach = Int((columns.glyphSize ?? roughGlyph) * 0.4) + 12
        let near = BlockScene(cropping: scene, to: InkMask.nearRect(scene, reach: reach))
        let nearStrokes = scene.window.crop(strokes, to: near.window.rect)
        var style = StyleEstimator.estimate(scene: near, ink: nearStrokes, columns: columns, cellCount: cells)
        if balloon == nil { style = sanityChecked(style, block: block, textRect: scene.textRect, cellCount: cells) }

        var kind = block.kind
        let erase: RegionMask?
        var interior: RegionMask?
        if let balloon {
            let masks = balloonMasks(scene: scene, balloon: balloon, ink: ink, style: style)
            erase = masks.erase
            interior = masks.interior
            kind = isCaptionBox(masks.interior, text: block.source) ? .caption : .dialogue
            if kind == .caption { style.face = .serif }
        } else {
            let halo = StyleEstimator.haloWidth(scene: near, ink: nearStrokes, fontSize: style.fontSize)
            let grow = 2 + max(style.outlineWidth, halo) + max(1, style.strokeWidth * 0.5)
            let nearInk = scene.window.crop(ink, to: near.window.rect)
            erase = RegionMask(plane: InkMask.grow(nearInk, window: near.window, radius: grow), in: near.window)
            // Outside a balloon the text is a note in the artist's hand, unless the detector
            // saw a balloon that the page's pixels could not confirm.
            if block.kind != .dialogue { style.face = .handwritten }
        }
        guard let erase else { return nil }
        return BlockAnalysis(
            index: index, textRect: scene.textRect, kind: kind, background: scene.background,
            interior: interior, erase: erase, columns: columns, style: style
        )
    }

    /// On artwork the measures can go far wrong: the ink may be part of the drawing. Where
    /// the measured size is nowhere near what the box and the number of characters allow,
    /// the size the text itself gives stands in, with the usual pitches.
    private func sanityChecked(_ style: TextStyle, block: TextBlock, textRect: PixelRect, cellCount: Int) -> TextStyle {
        var style = style
        style.weight = min(0.25, max(0.02, style.weight))
        let isVertical = style.isVertical
        guard let glyph = Columns.expectedGlyphSize(
            extent: isVertical ? textRect.width : textRect.height, length: isVertical ? textRect.height : textRect.width,
            cellCount: cellCount
        ) else { return style }
        let expected = glyph / StyleEstimator.inkShare
        guard style.fontSize < 0.55 * expected || style.fontSize > 1.8 * expected else { return style }
        style.fontSize = expected
        style.characterPitch = expected
        style.linePitch = expected * 1.35
        style.strokeWidth = expected * style.weight
        return style
    }

    /// The erase mask and the interior of a block in a balloon.
    ///
    /// The text is the holes in the balloon's fill that touch the block's box, grown a little
    /// and kept off the balloon's outline, plus the ink inside the box: a glyph that touches
    /// the outline is no hole. Erased text becomes balloon, so the interior has no notch where
    /// a glyph met the outline.
    private func balloonMasks(
        scene: BlockScene, balloon: BalloonInterior, ink: [UInt8], style: TextStyle
    ) -> (erase: RegionMask?, interior: RegionMask) {
        let window = scene.window
        // Everything erased lies within a few pixels of the text, so the masks are made in
        // a window around it.
        let near = PixelWindow(cropping: window, to: InkMask.nearRect(scene, reach: Int(style.outlineWidth) + 10))
        let width = near.width, height = near.height
        let fill = window.crop(balloon.fill, to: near.rect), filled = window.crop(balloon.filled, to: near.rect)
        let box = near.local(InkMask.searchRect(scene))
        var holes = [UInt8](repeating: 0, count: near.count)
        for index in 0..<near.count where filled[index] != 0 && fill[index] == 0 { holes[index] = 1 }
        var text = [UInt8](repeating: 0, count: near.count)
        for component in Morphology.components(holes, width: width, height: height) {
            guard !component.bounds.intersection(box).isEmpty else { continue }
            for pixel in component.pixels { text[Int(pixel)] = 1 }
        }
        let grownHoles = Morphology.dilate(text, width: width, height: height, radius: 2.5)
        let safe = Morphology.erode(filled, width: width, height: height, radius: 1.5)
        let grownInk = InkMask.grow(window.crop(ink, to: near.rect), window: near, radius: 2 + style.outlineWidth)
        let inner = near.local(scene.textRect.insetBy(-2, -2))
        var erase = [UInt8](repeating: 0, count: near.count)
        for index in 0..<near.count {
            let inBox = grownInk[index] != 0 && inner.contains(index % width, index / width)
            if (grownHoles[index] != 0 && safe[index] != 0) || inBox { erase[index] = 1 }
        }
        let eraseMask = RegionMask(plane: erase, in: near)
        var joined = balloon.filled
        if let eraseMask {
            for y in eraseMask.rect.y0..<eraseMask.rect.y1 {
                for x in eraseMask.rect.x0..<eraseMask.rect.x1 where eraseMask.contains(x, y) {
                    joined[window.index(x, y)] = 1
                }
            }
        }
        let interior = Morphology.fillHoles(joined, width: window.width, height: window.height)
        return (eraseMask, RegionMask(plane: interior, in: window) ?? RegionMask(rect: scene.textRect))
    }

    /// A caption box is a rectangle with a sentence in it: its interior fills its bounds, and
    /// it holds more than an exclamation.
    private func isCaptionBox(_ interior: RegionMask, text: String) -> Bool {
        let share = Double(interior.count) / Double(max(1, interior.rect.area))
        return share >= 0.9 && CharacterClass.letterCount(text) >= 6
    }
}

/// The classes of characters the analysis tells apart.
enum CharacterClass {
    static func isKana(_ scalar: Unicode.Scalar) -> Bool {
        (0x3040...0x30FF).contains(scalar.value) || (0x31F0...0x31FF).contains(scalar.value)
            || (0xFF66...0xFF9F).contains(scalar.value)
    }

    static func isHan(_ scalar: Unicode.Scalar) -> Bool {
        (0x4E00...0x9FFF).contains(scalar.value) || (0x3400...0x4DBF).contains(scalar.value)
            || (0xF900...0xFAFF).contains(scalar.value)
    }

    static func isLatinOrDigit(_ scalar: Unicode.Scalar) -> Bool {
        (0x30...0x39).contains(scalar.value) || (0x41...0x5A).contains(scalar.value)
            || (0x61...0x7A).contains(scalar.value) || (0xFF10...0xFF19).contains(scalar.value)
            || (0xFF21...0xFF3A).contains(scalar.value) || (0xFF41...0xFF5A).contains(scalar.value)
    }

    /// The number of letters in `text`: kana, kanji, Latin letters and digits, without
    /// punctuation and the long-vowel marks.
    static func letterCount(_ text: String) -> Int {
        text.unicodeScalars.reduce(0) { count, scalar in
            let isLetter = (isKana(scalar) || isHan(scalar) || isLatinOrDigit(scalar)) && scalar != "ー" && scalar != "〜"
            return count + (isLetter ? 1 : 0)
        }
    }
}

/// The analysis of every block of a page that will be drawn.
struct PageAnalysis: Sendable {
    var width: Int
    var height: Int
    var blocks: [BlockAnalysis]
}

struct PageAnalyzer: Sendable {
    var blockAnalyzer = BlockAnalyzer()

    /// Analyses the blocks that have a translation; blocks without one (sound effects that
    /// were not read among them) are left as they are. Checks for cancellation between blocks.
    func analyze(page: PageBitmap, blocks: [TextBlock]) throws -> PageAnalysis {
        var analyses: [BlockAnalysis] = []
        for (index, block) in blocks.enumerated() where Self.isDrawn(block) {
            try Task.checkCancellation()
            if let analysis = blockAnalyzer.analyze(page: page, block: block, index: index) {
                analyses.append(analysis)
            }
        }
        snapDialogueWeights(&analyses)
        return PageAnalysis(width: page.width, height: page.height, blocks: analyses)
    }

    /// A sound effect is drawn like any other block once it has a translation: it has one
    /// only when the switch for sound effects had it read.
    static func isDrawn(_ block: TextBlock) -> Bool {
        !block.translation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// One dialogue face for a page, as letterers use, and bold for shouting. Below a shout,
    /// the weight measured in one balloon says little: kana have thicker strokes than kanji
    /// in the same face, and small text measures heavier than large. So every block that is
    /// not a shout takes the page's median.
    private func snapDialogueWeights(_ analyses: inout [BlockAnalysis]) {
        let weights = analyses.filter { $0.isInBalloon && $0.style.face == .dialogue }.map(\.style.weight).sorted()
        guard !weights.isEmpty else { return }
        let median = weights[weights.count / 2]
        for index in analyses.indices where analyses[index].style.face == .dialogue {
            analyses[index].style.weight = median
        }
    }
}
