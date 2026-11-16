/// The face a block is lettered in. Handwriting cannot be told from type by measuring, so the
/// rule is where the text stands: in a balloon, in a caption box, or outside both.
enum LetteringFace: String, Sendable, CaseIterable {
    case dialogue, bold, handwritten, serif
}

enum TextAlignment: String, Sendable {
    case start, center, end
}

/// The lettering of a block as measured from its ink.
struct TextStyle: Sendable, Equatable {
    /// The size of a character cell, in pixels.
    var fontSize: Double
    /// The distance from one character to the next along a column.
    var characterPitch: Double
    /// The distance between the centres of neighbouring columns.
    var linePitch: Double
    /// The ink's extent across a column.
    var inkWidth: Double
    var ink: PixelColor
    /// The colour of a band drawn around the glyphs, when there is one.
    var outline: PixelColor?
    var outlineWidth: Double
    /// The thickness of the glyphs' strokes, in pixels.
    var strokeWidth: Double
    /// `strokeWidth / fontSize`, which picks the weight of the face.
    var weight: Double
    var isVertical: Bool
    var alignment: TextAlignment
    var face: LetteringFace

    /// From this weight up, the lettering is a shout.
    static let boldWeight = 0.14
}

enum StyleEstimator {
    /// The share of its square that the ink of a column of glyphs spans across.
    static let inkShare = 0.88

    /// - Parameters:
    ///   - ink: the block's ink as a plane the size of the scene's window.
    ///   - cellCount: how many character cells the block's text takes; 0 when unknown.
    static func estimate(scene: BlockScene, ink: [UInt8], columns: BlockColumns, cellCount: Int) -> TextStyle {
        let isVertical = columns.isVertical
        let base = columns.base
        let glyph = columns.glyphSize ?? Double(min(scene.textRect.width, scene.textRect.height))
        var widths: [Double] = []
        var totalLength = 0.0
        for column in base {
            totalLength += Double(isVertical ? column.rect.height : column.rect.width)
            if let width = inkExtent(ink, window: scene.window, column: column.rect, isVertical: isVertical) {
                widths.append(width)
            }
        }
        let inkWidth = median(widths) ?? glyph
        let sizeFromInk = inkWidth / Self.inkShare
        // The advance of a character, from the columns' lengths and the number of cells: a
        // column of n cells is n advances long, less the tenth of a cell its last glyph
        // leaves empty.
        let cells = max(0.5, Double(cellCount) - 0.1 * Double(base.count))
        let pitch = cellCount > 0 && totalLength > 0 ? totalLength / cells : nil
        let fontSize: Double
        if let pitch, cellCount >= 3 {
            fontSize = abs(sizeFromInk / pitch - 1) < 0.25 ? (pitch + sizeFromInk) / 2 : pitch
        } else if let pitch, abs(sizeFromInk / pitch - 1) < 0.4 {
            // A word or two: kana are narrower than their square, so the larger measure is
            // the nearer one.
            fontSize = max(pitch, sizeFromInk)
        } else {
            fontSize = sizeFromInk
        }
        let centres = base.map { isVertical ? $0.rect.midX : $0.rect.midY }.sorted()
        var gaps: [Double] = []
        for (near, far) in zip(centres, centres.dropFirst()) {
            let gap = far - near
            if gap > 0.6 * fontSize, gap < 2.6 * fontSize { gaps.append(gap) }
        }
        let (inkColor, strokes) = inkColorAndStrokes(scene: scene, ink: ink)
        let stroke = trimmedMean(strokes) ?? fontSize * 0.08
        let outline = detectOutline(scene: scene, ink: ink, inkColor: inkColor, fontSize: fontSize)
        let weight = stroke / max(1, fontSize)
        return TextStyle(
            fontSize: fontSize, characterPitch: pitch ?? fontSize, linePitch: median(gaps) ?? fontSize * 1.35,
            inkWidth: inkWidth, ink: inkColor, outline: outline?.color, outlineWidth: outline?.width ?? 0,
            strokeWidth: stroke, weight: weight, isVertical: isVertical,
            alignment: alignment(of: base, isVertical: isVertical, fontSize: fontSize),
            face: weight >= TextStyle.boldWeight ? .bold : .dialogue
        )
    }

    /// Where the columns start: together, as letterers set them, or centred.
    private static func alignment(of columns: [TextColumn], isVertical: Bool, fontSize: Double) -> TextAlignment {
        // A column of a character or two says nothing about alignment.
        let long = columns.filter { Double(isVertical ? $0.rect.height : $0.rect.width) >= 2.5 * fontSize }
        guard long.count >= 2 else { return columns.count < 2 ? .center : .start }
        func spread(_ values: [Double]) -> Double { (values.max() ?? 0) - (values.min() ?? 0) }
        let starts = spread(long.map { Double(isVertical ? $0.rect.y0 : $0.rect.x0) })
        let ends = spread(long.map { Double(isVertical ? $0.rect.y1 : $0.rect.x1) })
        let centres = spread(long.map { isVertical ? $0.rect.midY : $0.rect.midX })
        if starts <= 0.35 * fontSize || (starts <= ends && starts <= centres) { return .start }
        return centres <= ends ? .center : .end
    }

    /// The mean of the middle half: a continuous estimate from whole-number samples.
    static func trimmedMean(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted[(sorted.count / 4)...max(sorted.count / 4, sorted.count * 3 / 4 - 1)]
        return middle.reduce(0, +) / Double(middle.count)
    }

    static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.sorted()[values.count / 2]
    }

    /// The extent of the ink across a column, between its 2nd and 98th percentiles.
    private static func inkExtent(_ ink: [UInt8], window: PixelWindow, column: PixelRect, isVertical: Bool) -> Double? {
        let local = window.local(column)
        var counts = [Int](repeating: 0, count: isVertical ? local.width : local.height)
        var total = 0
        for y in local.y0..<local.y1 {
            for x in local.x0..<local.x1 where ink[y * window.width + x] != 0 {
                counts[isVertical ? x - local.x0 : y - local.y0] += 1
                total += 1
            }
        }
        guard total > 20 else { return nil }
        var seen = 0, low = 0, high = counts.count - 1
        for (index, count) in counts.enumerated() {
            if seen * 100 <= total * 2 { low = index }
            seen += count
            if seen * 100 >= total * 98 {
                high = index
                break
            }
        }
        return Double(high - low + 1)
    }

    /// The ink's colour, from the third of its pixels that differ most from the background
    /// (the rest are anti-aliased edges), and samples of the stroke thickness, from the ridge
    /// of the distance to the ink's edge.
    static func inkColorAndStrokes(scene: BlockScene, ink: [UInt8]) -> (PixelColor, [Double]) {
        let window = scene.window, width = window.width, height = window.height
        var byDifference = [[Int32]](repeating: [], count: 256)
        var total = 0
        for index in 0..<ink.count where ink[index] != 0 {
            byDifference[Int(scene.difference[index])].append(Int32(index))
            total += 1
        }
        var colors = ColorHistogram()
        let wanted = max(1, total / 3)
        for difference in stride(from: 255, through: 0, by: -1) where colors.count < wanted {
            for index in byDifference[difference] where colors.count < wanted {
                colors.add(window.color(Int(index)))
            }
        }
        return (colors.median ?? .black, strokeSamples(ink, width: width, height: height))
    }

    /// Stroke thickness at every local maximum of the distance from inside the ink to its edge.
    static func strokeSamples(_ ink: [UInt8], width: Int, height: Int) -> [Double] {
        guard width > 2, height > 2 else { return [] }
        let distance = Morphology.squaredDistance(ink, width: width, height: height, toSet: false)
        var strokes: [Double] = []
        distance.withUnsafeBufferPointer { values in
            for y in 1..<(height - 1) {
                for x in 1..<(width - 1) {
                    let value = values[y * width + x]
                    guard value > 0 else { continue }
                    var isRidge = true
                    for dy in -1...1 {
                        for dx in -1...1 where values[(y + dy) * width + x + dx] > value { isRidge = false }
                    }
                    if isRidge { strokes.append(2 * Double(value).squareRoot() - 1) }
                }
            }
        }
        return strokes
    }

    /// The median colour of the window's pixels at each whole distance from the ink, up to
    /// `reach`: the rings an outline or a glow shows up in.
    private static func rings(scene: BlockScene, ink: [UInt8], reach: Int) -> [PixelColor?] {
        let window = scene.window
        let distance = Morphology.squaredDistance(ink, width: window.width, height: window.height)
        var rings = [ColorHistogram](repeating: ColorHistogram(), count: reach + 1)
        let limit = Float(reach * reach)
        for index in 0..<distance.count where distance[index] > 0 && distance[index] <= limit {
            let ring = Int(Double(distance[index]).squareRoot().rounded(.up))
            if ring <= reach { rings[ring].add(window.color(index)) }
        }
        return rings.map(\.median)
    }

    /// A band of one colour around the glyphs that differs from both the ink and what lies
    /// beyond it, with its width.
    static func detectOutline(
        scene: BlockScene, ink: [UInt8], inkColor: PixelColor, fontSize: Double
    ) -> (color: PixelColor, width: Double)? {
        let reach = max(4, Int(fontSize * 0.3))
        let rings = rings(scene: scene, ink: ink, reach: reach + 5)
        var beyond = ColorHistogram()
        for ring in rings[(reach + 2)...] { if let ring { beyond.add(ring) } }
        guard let near = rings[2], let far = beyond.median,
              near.difference(far) >= 60, near.difference(inkColor) >= 60
        else { return nil }
        var width = 2.0
        for ring in 3...reach {
            guard let color = rings[ring], color.difference(near) < 40 else { break }
            width = Double(ring)
        }
        return (near, width)
    }

    /// The width of a faint glow or soft outline around the glyphs: how far the rings stay
    /// distinct from what lies beyond them. Too faint to draw again, but the eraser must cover
    /// it or a ghost of the old text remains.
    static func haloWidth(scene: BlockScene, ink: [UInt8], fontSize: Double) -> Double {
        let reach = max(4, Int(fontSize * 0.35))
        let rings = rings(scene: scene, ink: ink, reach: reach + 6)
        var beyond = ColorHistogram()
        for ring in rings[(reach + 3)...] { if let ring { beyond.add(ring) } }
        guard let far = beyond.median else { return 0 }
        var width = 0.0
        for ring in 1...reach {
            guard let color = rings[ring], color.difference(far) >= 12 else { break }
            width = Double(ring)
        }
        return width
    }
}
