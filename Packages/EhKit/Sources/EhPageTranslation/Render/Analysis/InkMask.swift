/// The glyph pixels of a block: the pixels in its box that differ from the background.
enum InkMask {
    /// The ink as a plane the size of the scene's window, before anything is known about the
    /// balloon or the size of the glyphs.
    ///
    /// Ink has one polarity. When pixels both darker and lighter than the background differ
    /// from it, one of the two is an outline band drawn around the other: the band is the set
    /// that touches the background.
    static func candidates(scene: BlockScene) -> [UInt8] {
        let window = scene.window, width = window.width
        let box = window.local(searchRect(scene))
        guard !box.isEmpty else { return [UInt8](repeating: 0, count: window.count) }
        var histogram = [Int](repeating: 0, count: 256)
        for y in box.y0..<box.y1 {
            for x in box.x0..<box.x1 { histogram[Int(scene.difference[y * width + x])] += 1 }
        }
        let threshold = min(120, max(40, Otsu.threshold(histogram)))
        let backgroundLuma = scene.background.luma
        var darker = 0, lighter = 0, darkEdge = 0, lightEdge = 0
        for y in box.y0..<box.y1 {
            for x in box.x0..<box.x1 {
                let index = y * width + x
                guard Int(scene.difference[index]) >= threshold else { continue }
                var touchesBackground = false
                if x > 0, Int(scene.difference[index - 1]) < threshold / 2 { touchesBackground = true }
                if x < width - 1, Int(scene.difference[index + 1]) < threshold / 2 { touchesBackground = true }
                if y > 0, Int(scene.difference[index - width]) < threshold / 2 { touchesBackground = true }
                if y < window.height - 1, Int(scene.difference[index + width]) < threshold / 2 { touchesBackground = true }
                if Int(scene.luma[index]) < backgroundLuma {
                    darker += 1
                    if touchesBackground { darkEdge += 1 }
                } else {
                    lighter += 1
                    if touchesBackground { lightEdge += 1 }
                }
            }
        }
        let inkIsDarker: Bool
        if lighter < (darker + lighter) / 8 {
            inkIsDarker = true
        } else if darker < (darker + lighter) / 8 {
            inkIsDarker = false
        } else {
            inkIsDarker = Double(darkEdge) / Double(darker) <= Double(lightEdge) / Double(lighter)
        }
        var bits = [UInt8](repeating: 0, count: window.count)
        for y in box.y0..<box.y1 {
            for x in box.x0..<box.x1 {
                let index = y * width + x
                if Int(scene.difference[index]) >= threshold, (Int(scene.luma[index]) < backgroundLuma) == inkIsDarker {
                    bits[index] = 1
                }
            }
        }
        return bits
    }

    /// The ink of a block in a balloon: inside the balloon, or inside the block's own box,
    /// where a glyph that touches the outline still counts.
    static func insideBalloon(_ candidates: [UInt8], scene: BlockScene, interior: [UInt8]) -> [UInt8] {
        let window = scene.window
        let text = window.local(scene.textRect)
        var bits = candidates
        for index in 0..<bits.count where bits[index] != 0 && interior[index] == 0 {
            if !text.contains(index % window.width, index / window.width) { bits[index] = 0 }
        }
        return bits
    }

    /// The ink of a block that stands on artwork.
    ///
    /// Artwork has no one colour behind the text, so the difference from a background colour,
    /// which serves in a balloon, finds too little here. Otsu's split of the box's brightness
    /// gives two classes, and the ink is taken from the one the box's border is not in.
    /// Unless the lettering is the border's own class enclosed by the other: white lettering
    /// on a dark patch or a screentone, or inside a thick dark band. A piece that reaches the
    /// box's edge and is too large to be glyphs is never ink.
    ///
    /// What is left still holds more than glyphs. Lines of the drawing that cross the box
    /// (speed lines, hair) leave it by a long way: those are dropped, unless most of the ink
    /// hangs on them, as it does when a note is written across an outline. The dots of a
    /// screentone are far smaller than a stroke: they go too, except right beside one, where
    /// they may be the marks of a voiced kana or a full stop.
    ///
    /// - Returns: `strokes`, the pieces large enough to be strokes of glyphs, which the
    ///   columns and the style are measured on; and `all`, with the small marks beside them,
    ///   which is what is erased.
    static func onArtwork(scene: BlockScene, glyphSize: Double) -> (strokes: [UInt8], all: [UInt8]) {
        let window = scene.window, width = window.width, height = window.height
        let box = window.local(searchRect(scene))
        let empty = [UInt8](repeating: 0, count: window.count)
        guard box.width > 2, box.height > 2 else { return (empty, empty) }
        func touchesEdge(_ bounds: PixelRect) -> Bool {
            bounds.x0 <= box.x0 || bounds.y0 <= box.y0 || bounds.x1 >= box.x1 || bounds.y1 >= box.y1
        }
        func size(_ component: Morphology.Component) -> Int { max(component.bounds.width, component.bounds.height) }
        func isBlob(_ component: Morphology.Component) -> Bool {
            component.pixels.count * 100 > 15 * box.area && Double(size(component)) > 1.6 * glyphSize
        }
        func pixelCount(_ components: [Morphology.Component]) -> Int { components.reduce(0) { $0 + $1.pixels.count } }

        let (inside, outside) = brightnessClasses(scene: scene, box: box)
        // The class off the border, without what reaches the box's edge and is too large to
        // be glyphs (the artwork itself); and the pieces of the border's class that stand
        // clear of the edge.
        let allOffBorder = Morphology.components(inside, width: width, height: height)
        let offBorder = allOffBorder.filter { !(isBlob($0) && touchesEdge($0.bounds)) }
        let clear = Morphology.components(outside, width: width, height: height)
            .filter { !touchesEdge($0.bounds) && !isBlob($0) }
        var components = offBorder
        let offBorderCount = pixelCount(offBorder)
        if pixelCount(clear) > 2 * offBorderCount {
            // Little is off the border but specks: white lettering on a screentone.
            components = clear
        } else {
            // A band or a patch holds much of the other class inside it, and that holds
            // nothing more: the lettering is what it holds. Glyphs hold only their counters,
            // and a second band round a first holds a band that holds the glyphs. A band may
            // reach the box's edge, so the pieces dropped above count as holders too.
            let holders = allOffBorder.filter { holder in clear.contains { Self.holds(holder.bounds, $0.bounds) } }
            let held = clear.filter { piece in holders.contains { Self.holds($0.bounds, piece.bounds) } }
            let heldCount = pixelCount(held)
            let edgeHolders = holders.filter { isBlob($0) && touchesEdge($0.bounds) }
            if heldCount * 100 >= 15 * (offBorderCount + pixelCount(edgeHolders)) {
                let deeper = offBorder.filter { piece in held.contains { Self.holds($0.bounds, piece.bounds) } }
                // Counters are a small part of their glyphs; a band's glyphs are not.
                if pixelCount(deeper) * 100 < 30 * heldCount { components = held }
            }
        }

        let crossing = components.filter { touchesEdge($0.bounds) && Double(size($0)) > 1.5 * glyphSize }
        if pixelCount(crossing) * 2 < pixelCount(components) {
            components.removeAll { touchesEdge($0.bounds) && Double(size($0)) > 1.5 * glyphSize }
        }
        // The size of the piece that holds the median ink pixel: a stroke, unless the tone
        // outweighs the text.
        let sizes = components.map { (size: size($0), pixels: $0.pixels.count) }.sorted { $0.size < $1.size }
        let kept = sizes.reduce(0) { $0 + $1.pixels }
        var seen = 0, typical = 0
        for entry in sizes {
            seen += entry.pixels
            if seen * 2 >= kept {
                typical = entry.size
                break
            }
        }
        let smallest = max(3, typical * 3 / 10)
        var strokes = empty
        for component in components where size(component) >= smallest {
            for pixel in component.pixels { strokes[Int(pixel)] = 1 }
        }
        let near = Morphology.dilateSquare(strokes, width: width, height: height, radius: max(2, typical / 4))
        var all = strokes
        for component in components where size(component) < smallest {
            guard component.pixels.contains(where: { near[Int($0)] != 0 }) else { continue }
            for pixel in component.pixels { all[Int(pixel)] = 1 }
        }
        return (strokes, all)
    }

    /// Whether `inner` lies within `outer`.
    private static func holds(_ outer: PixelRect, _ inner: PixelRect) -> Bool {
        inner.x0 >= outer.x0 && inner.y0 >= outer.y0 && inner.x1 <= outer.x1 && inner.y1 <= outer.y1
    }

    /// The pixels of `box` on either side of Otsu's split of its brightness: `inside`, the
    /// class the box's border is not in, and `outside`, the border's own.
    private static func brightnessClasses(scene: BlockScene, box: PixelRect) -> (inside: [UInt8], outside: [UInt8]) {
        let width = scene.window.width
        var histogram = [Int](repeating: 0, count: 256), border = [Int](repeating: 0, count: 256)
        for y in box.y0..<box.y1 {
            for x in box.x0..<box.x1 {
                let luma = Int(scene.luma[y * width + x])
                histogram[luma] += 1
                if x == box.x0 || y == box.y0 || x == box.x1 - 1 || y == box.y1 - 1 { border[luma] += 1 }
            }
        }
        let threshold = Otsu.threshold(histogram)
        let borderCount = border.reduce(0, +)
        var seen = 0, borderMedian = 255
        for value in 0..<256 {
            seen += border[value]
            if seen * 2 >= borderCount {
                borderMedian = value
                break
            }
        }
        let borderIsDark = borderMedian <= threshold
        var inside = [UInt8](repeating: 0, count: scene.window.count), outside = inside
        for y in box.y0..<box.y1 {
            for x in box.x0..<box.x1 {
                let index = y * width + x
                if (Int(scene.luma[index]) > threshold) == borderIsDark { inside[index] = 1 } else { outside[index] = 1 }
            }
        }
        return (inside, outside)
    }

    /// The block's box, grown a little: a detector's box often cuts the outermost strokes.
    static func searchRect(_ scene: BlockScene) -> PixelRect {
        let text = scene.textRect
        let pad = min(12, max(3, min(text.width, text.height) * 6 / 100))
        return text.insetBy(-pad, -pad).intersection(scene.window.rect)
    }

    /// `plane` grown by `radius`.
    static func grow(_ plane: [UInt8], window: PixelWindow, radius: Double) -> [UInt8] {
        Morphology.dilate(plane, width: window.width, height: window.height, radius: radius)
    }

    /// The part of the scene that holds the text and what is erased around it: the measures
    /// and the masks are made there and not over the whole balloon.
    static func nearRect(_ scene: BlockScene, reach: Int) -> PixelRect {
        searchRect(scene).insetBy(-reach, -reach).intersection(scene.window.rect)
    }
}
