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

    /// The ink of a block on artwork, which holds more than glyphs.
    ///
    /// Lines of the drawing that cross the box (speed lines, hair) leave it by a long way:
    /// those are dropped. The dots of a screentone are far smaller than a stroke: they are
    /// dropped too, unless they stand right beside one, where they may be the marks of a
    /// voiced kana or a full stop.
    ///
    /// - Returns: `strokes`, the pieces large enough to be strokes of glyphs, which the
    ///   columns and the style are measured on; and `all`, with the small marks beside them,
    ///   which is what is erased.
    static func onArtwork(
        _ candidates: [UInt8], scene: BlockScene, glyphSize: Double
    ) -> (strokes: [UInt8], all: [UInt8]) {
        let window = scene.window, width = window.width, height = window.height
        let box = window.local(searchRect(scene))
        var components = Morphology.components(candidates, width: width, height: height)
        components.removeAll { component in
            let bounds = component.bounds
            let touchesEdge = bounds.x0 <= box.x0 || bounds.y0 <= box.y0 || bounds.x1 >= box.x1 || bounds.y1 >= box.y1
            return touchesEdge && Double(max(bounds.width, bounds.height)) > 1.5 * glyphSize
        }
        // The size of the piece that holds the median ink pixel: a stroke, unless the tone
        // outweighs the text.
        let sizes = components.map { (size: max($0.bounds.width, $0.bounds.height), pixels: $0.pixels.count) }
            .sorted { $0.size < $1.size }
        let total = sizes.reduce(0) { $0 + $1.pixels }
        var seen = 0, typical = 0
        for entry in sizes {
            seen += entry.pixels
            if seen * 2 >= total {
                typical = entry.size
                break
            }
        }
        let smallest = max(3, typical * 3 / 10)
        var strokes = [UInt8](repeating: 0, count: window.count)
        for component in components where max(component.bounds.width, component.bounds.height) >= smallest {
            for pixel in component.pixels { strokes[Int(pixel)] = 1 }
        }
        let near = Morphology.dilateSquare(strokes, width: width, height: height, radius: max(2, typical / 4))
        var all = strokes
        for component in components where max(component.bounds.width, component.bounds.height) < smallest {
            guard component.pixels.contains(where: { near[Int($0)] != 0 }) else { continue }
            for pixel in component.pixels { all[Int(pixel)] = 1 }
        }
        return (strokes, all)
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
