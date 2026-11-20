/// The inside of a balloon or caption box, as planes the size of the block's window.
struct BalloonInterior: Sendable {
    /// The light pixels the fill reached from the text, in one piece: the balloon's white
    /// without the pockets its lettering encloses.
    var fill: [UInt8]
    /// The whole inside: `fill`, the pockets, the glyphs and anything else drawn in the
    /// balloon.
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
    /// The same for a balloon the detector saw: heavy lettering that touches the outline
    /// leaves the fill only the pockets between its strokes.
    var hintedMinimumCoverage = 0.4
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
        guard let fill = seededFill(passable: passable, scene: scene, isBoundedByMask: hint?.mask != nil) else {
            return nil
        }
        let filled = Morphology.fillHoles(fill.all, width: width, height: height)
        let area = Morphology.count(filled)
        if hint == nil, Double(area) > maximumAreaRatio * Double(max(1, scene.textRect.area)) { return nil }
        let covered = coverage(of: scene.textRect, by: filled, window: window)
        guard covered >= (hint == nil ? minimumCoverage : hintedMinimumCoverage) else { return nil }
        let rim = max(6, Int(glyphSize * 0.6))
        let outline = outlineScore(filled: filled, scene: scene, rim: rim)
        guard outline >= (hint == nil ? minimumOutline : hintedMinimumOutline) else { return nil }
        return BalloonInterior(fill: fill.main, filled: filled, outline: outline)
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
        wall.withUnsafeBufferPointer { wall in
            scene.difference.withUnsafeBufferPointer { difference in
                passable.withUnsafeMutableBufferPointer { open in
                    for index in 0..<open.count where wall[index] == 0 && difference[index] <= tolerance { open[index] = 1 }
                    if let allowed {
                        allowed.withUnsafeBufferPointer { allowed in
                            for index in 0..<open.count where allowed[index] == 0 { open[index] = 0 }
                        }
                    }
                }
            }
        }
        return passable
    }

    /// The passable areas that hold the background pixels in and around the text's box.
    ///
    /// The area with most of them is the balloon; voting keeps out the paper beyond a corner
    /// of the box that pokes out of a round balloon. The smaller ones are the pockets heavy
    /// lettering cuts the balloon's white into, and belong to it too. Without a mask to stop
    /// it, an area that reaches the window's edge has leaked into the page, unless that edge
    /// is the page's own: a balloon may be cut by it. `nil` when the main area leaked or the
    /// text stands on too little background.
    ///
    /// - Returns: `main`, the area with the most background pixels, and `all`, with the
    ///   pockets.
    func seededFill(passable: [UInt8], scene: BlockScene, isBoundedByMask: Bool) -> (main: [UInt8], all: [UInt8])? {
        let window = scene.window, width = window.width, height = window.height
        let text = scene.textRect
        let pad = max(4, min(text.width, text.height) / 6)
        let seeds = window.local(text.insetBy(-pad, -pad))
        let openLeft = !window.touchesPageEdge(left: true), openRight = !window.touchesPageEdge(right: true)
        let openTop = !window.touchesPageEdge(top: true), openBottom = !window.touchesPageEdge(bottom: true)
        var owner = [Int32](repeating: -1, count: window.count)
        var votes: [Int] = [], leaks: [Bool] = []
        var stack: [Int32] = []
        var seedCount = 0
        let tolerance = UInt8(seedTolerance)
        passable.withUnsafeBufferPointer { open in
            scene.difference.withUnsafeBufferPointer { difference in
                owner.withUnsafeMutableBufferPointer { labels in
                    for y in seeds.y0..<seeds.y1 {
                        for x in seeds.x0..<seeds.x1 {
                            let start = y * width + x
                            guard open[start] != 0, difference[start] <= tolerance else { continue }
                            seedCount += 1
                            if labels[start] >= 0 {
                                votes[Int(labels[start])] += 1
                                continue
                            }
                            let label = Int32(votes.count)
                            var leaked = false
                            labels[start] = label
                            stack.append(Int32(start))
                            while let next = stack.popLast() {
                                let index = Int(next), px = index % width, py = index / width
                                if px > 0 {
                                    if open[index - 1] != 0, labels[index - 1] < 0 {
                                        labels[index - 1] = label
                                        stack.append(Int32(index - 1))
                                    }
                                } else if openLeft { leaked = true }
                                if px < width - 1 {
                                    if open[index + 1] != 0, labels[index + 1] < 0 {
                                        labels[index + 1] = label
                                        stack.append(Int32(index + 1))
                                    }
                                } else if openRight { leaked = true }
                                if py > 0 {
                                    if open[index - width] != 0, labels[index - width] < 0 {
                                        labels[index - width] = label
                                        stack.append(Int32(index - width))
                                    }
                                } else if openTop { leaked = true }
                                if py < height - 1 {
                                    if open[index + width] != 0, labels[index + width] < 0 {
                                        labels[index + width] = label
                                        stack.append(Int32(index + width))
                                    }
                                } else if openBottom { leaked = true }
                            }
                            votes.append(1)
                            leaks.append(leaked)
                        }
                    }
                }
            }
        }
        guard seedCount >= 12, let best = votes.indices.max(by: { votes[$0] < votes[$1] }) else { return nil }
        if !isBoundedByMask, leaks[best] { return nil }
        var kept = [Bool](repeating: false, count: votes.count)
        var keptVotes = 0
        for label in votes.indices where votes[label] >= 2 && (isBoundedByMask || !leaks[label]) {
            kept[label] = true
            keptVotes += votes[label]
        }
        guard keptVotes * 3 >= seedCount else { return nil }
        let main = Int32(best)
        return (owner.map { $0 == main ? 1 : 0 }, owner.map { $0 >= 0 && kept[Int($0)] ? 1 : 0 })
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
        let backgroundLuma = scene.background.luma
        let originX = window.rect.x0, originY = window.rect.y0
        var drawn = 0, atPageEdge = 0, total = 0
        filled.withUnsafeBufferPointer { filled in
            scene.luma.withUnsafeBufferPointer { luma in
                scene.difference.withUnsafeBufferPointer { difference in
                    /// 1 for an outline, 2 for the page's edge, 0 for neither, looking outwards
                    /// from (`x`, `y`) along (`dx`, `dy`).
                    func edge(_ x: Int, _ y: Int, _ dx: Int, _ dy: Int) -> Int {
                        for step in 1...rim {
                            let nx = x + dx * step, ny = y + dy * step
                            let pageX = nx + originX, pageY = ny + originY
                            if pageX < 0 || pageY < 0 || pageX >= window.pageWidth || pageY >= window.pageHeight { return 2 }
                            guard nx >= 0, ny >= 0, nx < width, ny < height else { return 0 }
                            let index = ny * width + nx
                            let brightness = Int(luma[index])
                            if difference[index] >= 80, brightness <= backgroundLuma - 40 { return 1 }
                            // Past a few pixels, keep looking only across a light rim: a
                            // coloured balloon often fades to white before its outline.
                            if step >= 6, brightness < 200 { return 0 }
                        }
                        return 0
                    }
                    for y in 0..<height {
                        let row = y * width
                        for x in 0..<width where filled[row + x] != 0 {
                            var dx = 0, dy = 0
                            if x == width - 1 || filled[row + x + 1] == 0 {
                                dx = 1
                            } else if x == 0 || filled[row + x - 1] == 0 {
                                dx = -1
                            } else if y == height - 1 || filled[row + width + x] == 0 {
                                dy = 1
                            } else if y == 0 || filled[row - width + x] == 0 {
                                dy = -1
                            } else {
                                continue
                            }
                            total += 1
                            switch edge(x, y, dx, dy) {
                            case 1: drawn += 1
                            case 2: atPageEdge += 1
                            default: break
                            }
                        }
                    }
                }
            }
        }
        return total > 0 ? Double(drawn + min(atPageEdge, total / 2)) / Double(total) : 0
    }
}
