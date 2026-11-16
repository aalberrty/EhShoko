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

    init(page: PageBitmap, block: TextBlock) {
        let text = PixelRect(covering: block.box).clamped(width: page.width, height: page.height)
        let hint = block.balloon.map { PixelRect(covering: $0.box) }
        let window = PixelWindow(page: page, rect: Self.windowRect(text: text, balloon: hint))
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

/// The inside of a balloon or caption box, as planes the size of the block's window.
struct BalloonInterior: Sendable {
    /// The light pixels the fill reached.
    var fill: [UInt8]
    /// `fill` with its holes closed: the glyphs and anything else drawn inside the balloon.
    var filled: [UInt8]
    /// The share of the interior's edge that meets a drawn outline or the page's edge.
    var outline: Double
}

/// Finds the closed light area a block of text stands in, by a flood fill of the page's
/// pixels from the text. The detector's balloon only says where to look and how far the fill
/// may go: its mask is too coarse, and on the Neural Engine a pixel or two off, to erase or
/// letter by.
struct BalloonFinder: Sendable {
    /// How far a pixel may differ from the background and still start the fill.
    var seedTolerance = 36
    /// How far a pixel may differ from the background and still be filled.
    var fillTolerance = 52
    /// Pixels darker than this are outline; grown by two pixels they are walls, so a thin
    /// anti-aliased outline has no gap the fill could leak through.
    var darkLuma = 150
    var minimumOutline = 0.55
    /// A balloon the detector saw needs less proof from its outline.
    var hintedMinimumOutline = 0.35
    /// A balloon is at most this many times the area of its text.
    var maximumAreaRatio = 45.0
    /// The share of the text's box that must lie inside the balloon.
    var minimumCoverage = 0.75
    /// How far beyond the detector's mask the fill may go. Less than an outline is thick:
    /// through a gap in the outline, a wider margin would let the fill run round the outside
    /// of the balloon.
    var maskSlack = 3
    /// A balloon is light: the fill starts from a background at least this bright. White text
    /// in a dark balloon is erased and lettered as text on artwork.
    var minimumBackgroundLuma = 120

    func find(scene: BlockScene, hint: Balloon?, glyphSize: Double) -> BalloonInterior? {
        let window = scene.window, width = window.width, height = window.height
        guard width > 2, height > 2, !scene.textRect.isEmpty, scene.background.luma >= minimumBackgroundLuma else {
            return nil
        }
        let passable = passablePlane(scene: scene, hint: hint)
        guard let fill = dominantFill(passable: passable, scene: scene) else { return nil }
        // Without a mask to stop it, a fill that reaches the window's edge has leaked into the
        // page, unless that edge is the page's own: a balloon may be cut by it.
        if hint?.mask == nil, touchesOpenEdge(fill, window: window) { return nil }
        let filled = Morphology.fillHoles(fill, width: width, height: height)
        let area = Morphology.count(filled)
        if hint == nil, Double(area) > maximumAreaRatio * Double(max(1, scene.textRect.area)) { return nil }
        guard coverage(of: scene.textRect, by: filled, window: window) >= minimumCoverage else { return nil }
        let rim = max(6, Int(glyphSize * 0.6))
        let outline = outlineScore(filled: filled, scene: scene, rim: rim)
        guard outline >= (hint == nil ? minimumOutline : hintedMinimumOutline) else { return nil }
        return BalloonInterior(fill: fill, filled: filled, outline: outline)
    }

    /// Where the fill may go: light pixels near the background's colour that are not walls
    /// and, with a mask, not far outside it.
    func passablePlane(scene: BlockScene, hint: Balloon?) -> [UInt8] {
        let window = scene.window, width = window.width, height = window.height
        let dark = scene.luma.map { $0 < UInt8(darkLuma) ? UInt8(1) : 0 }
        let wall = Morphology.dilateSquare(dark, width: width, height: height, radius: 2)
        var allowed: [UInt8]?
        if let mask = hint?.mask {
            allowed = Morphology.dilateSquare(mask.plane(in: window), width: width, height: height, radius: maskSlack)
        }
        var passable = [UInt8](repeating: 0, count: window.count)
        let tolerance = UInt8(fillTolerance)
        for index in 0..<window.count where wall[index] == 0 && scene.difference[index] <= tolerance {
            if let allowed, allowed[index] == 0 { continue }
            passable[index] = 1
        }
        return passable
    }

    /// The connected passable area that holds most of the background pixels in and around the
    /// text's box. Voting keeps out a glyph's counter (the inside of 口) and the paper beyond
    /// a corner of the box that pokes out of a round balloon.
    func dominantFill(passable: [UInt8], scene: BlockScene) -> [UInt8]? {
        let window = scene.window, width = window.width, height = window.height
        let text = scene.textRect
        let pad = max(4, min(text.width, text.height) / 6)
        let seeds = window.local(text.insetBy(-pad, -pad))
        var owner = [Int32](repeating: -1, count: window.count)
        var votes: [Int] = []
        var stack: [Int32] = []
        var seedCount = 0
        let tolerance = UInt8(seedTolerance)
        passable.withUnsafeBufferPointer { open in
            owner.withUnsafeMutableBufferPointer { labels in
                for y in seeds.y0..<seeds.y1 {
                    for x in seeds.x0..<seeds.x1 {
                        let start = y * width + x
                        guard open[start] != 0, scene.difference[start] <= tolerance else { continue }
                        seedCount += 1
                        if labels[start] >= 0 {
                            votes[Int(labels[start])] += 1
                            continue
                        }
                        let label = Int32(votes.count)
                        votes.append(1)
                        labels[start] = label
                        stack.append(Int32(start))
                        while let next = stack.popLast() {
                            let index = Int(next), px = index % width, py = index / width
                            func visit(_ near: Int) {
                                if open[near] != 0, labels[near] < 0 {
                                    labels[near] = label
                                    stack.append(Int32(near))
                                }
                            }
                            if px > 0 { visit(index - 1) }
                            if px < width - 1 { visit(index + 1) }
                            if py > 0 { visit(index - width) }
                            if py < height - 1 { visit(index + width) }
                        }
                    }
                }
            }
        }
        guard seedCount >= 12, let best = votes.indices.max(by: { votes[$0] < votes[$1] }),
              votes[best] * 3 >= seedCount
        else { return nil }
        let chosen = Int32(best)
        return owner.map { $0 == chosen ? 1 : 0 }
    }

    func touchesOpenEdge(_ fill: [UInt8], window: PixelWindow) -> Bool {
        let width = window.width, height = window.height
        if !window.touchesPageEdge(top: true) {
            for x in 0..<width where fill[x] != 0 { return true }
        }
        if !window.touchesPageEdge(bottom: true) {
            for x in 0..<width where fill[(height - 1) * width + x] != 0 { return true }
        }
        if !window.touchesPageEdge(left: true) {
            for y in 0..<height where fill[y * width] != 0 { return true }
        }
        if !window.touchesPageEdge(right: true) {
            for y in 0..<height where fill[y * width + width - 1] != 0 { return true }
        }
        return false
    }

    func coverage(of rect: PixelRect, by plane: [UInt8], window: PixelWindow) -> Double {
        let local = window.local(rect)
        var inside = 0, total = 0
        for y in stride(from: local.y0, to: local.y1, by: 2) {
            for x in stride(from: local.x0, to: local.x1, by: 2) {
                total += 1
                if plane[y * window.width + x] != 0 { inside += 1 }
            }
        }
        return total > 0 ? Double(inside) / Double(total) : 0
    }

    /// The share of the interior's edge that meets a darker outline, or the page's edge,
    /// within a few pixels. A light area of artwork that only looks like a balloon has long
    /// stretches of edge with nothing drawn along them. The page's edge counts for half the
    /// outline at most: a balloon may be cut by it, but blank paper is no balloon.
    func outlineScore(filled: [UInt8], scene: BlockScene, rim: Int) -> Double {
        let window = scene.window, width = window.width, height = window.height
        var drawn = 0, atPageEdge = 0, total = 0
        let steps = [(1, 0), (-1, 0), (0, 1), (0, -1)]
        for y in 0..<height {
            for x in 0..<width where filled[y * width + x] != 0 {
                for (dx, dy) in steps {
                    let nx = x + dx, ny = y + dy
                    let outside = nx < 0 || ny < 0 || nx >= width || ny >= height || filled[ny * width + nx] == 0
                    guard outside else { continue }
                    total += 1
                    switch edge(fromX: x, y: y, dx: dx, dy: dy, rim: rim, scene: scene) {
                    case .outline: drawn += 1
                    case .pageEdge: atPageEdge += 1
                    case .none: break
                    }
                    break
                }
            }
        }
        return total > 0 ? Double(drawn + min(atPageEdge, total / 2)) / Double(total) : 0
    }

    private enum Edge { case outline, pageEdge, none }

    /// What lies just beyond the interior at (`x`, `y`), looking along (`dx`, `dy`).
    private func edge(fromX x: Int, y: Int, dx: Int, dy: Int, rim: Int, scene: BlockScene) -> Edge {
        let window = scene.window
        let backgroundLuma = scene.background.luma
        for step in 1...rim {
            let nx = x + dx * step, ny = y + dy * step
            let pageX = nx + window.rect.x0, pageY = ny + window.rect.y0
            if pageX < 0 || pageY < 0 || pageX >= window.pageWidth || pageY >= window.pageHeight { return .pageEdge }
            guard nx >= 0, ny >= 0, nx < window.width, ny < window.height else { return .none }
            let index = ny * window.width + nx
            let luma = Int(scene.luma[index])
            if Int(scene.difference[index]) >= 80, luma <= backgroundLuma - 40 { return .outline }
            // Past a few pixels, keep looking only across a light rim: a coloured balloon
            // often fades to white before its outline.
            if step >= 6, luma < 200 { return .none }
        }
        return .none
    }
}
