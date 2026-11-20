import CoreGraphics
import CoreText
import Foundation

/// Sets a translation with Core Text: vertical Chinese with the vertical forms of
/// punctuation, marks and short numbers upright in one square, longer Latin sideways, the
/// rules for what may start and end a column, and the fitting of size and columns to an area.
struct Typesetter: Sendable {
    /// The advance of one square, in ems.
    var tracking = 1.0
    /// The largest size tried, as a multiple of the original.
    var maximumGrowth = 1.08
    /// The smallest size tried, as a multiple of the original.
    var minimumShrink = 0.55
    /// No text is set smaller than this many pixels.
    var minimumPixelSize = 11.0
    /// The size falls by this factor from one try to the next.
    var step = 0.97

    // MARK: Measuring

    func advance(_ cell: TextCell, font: CTFont, fontSize: Double, isVertical: Bool) -> Double {
        guard isVertical else { return lineWidth(cell.text, font: font, isVertical: false) }
        switch cell.form {
        case .upright, .tateChuYoko: return fontSize * tracking
        case .sideways: return lineWidth(cell.text, font: font, isVertical: false) + fontSize * 0.15
        }
    }

    func lineWidth(_ text: String, font: CTFont, isVertical: Bool) -> Double {
        CTLineGetTypographicBounds(line(text, font, isVertical: isVertical), nil, nil, nil)
    }

    func line(_ text: String, _ font: CTFont, isVertical: Bool) -> CTLine {
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTVerticalFormsAttributeName as String): isVertical
        ]
        return CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
    }

    // MARK: Fitting

    /// The largest size, within the limits around the original, at which `text` fits `area`,
    /// with its columns. Text that fits at no size is set at the smallest and overflows.
    func fit(
        _ text: String, area: LayoutArea, style: TextStyle, isVertical: Bool, maximumGrowth: Double? = nil,
        fontAt: (Double) -> CTFont
    ) -> TextLayout {
        let cells = CellBuilder.cells(text, isVertical: isVertical)
        let pitchFactor = min(1.7, max(1.12, style.linePitch / max(1, style.fontSize)))
        let largest = style.fontSize * (maximumGrowth ?? self.maximumGrowth)
        let smallest = max(minimumPixelSize, style.fontSize * minimumShrink)
        var best: (layout: TextLayout, flaws: Int)?
        var size = largest
        while size >= smallest {
            let font = fontAt(size)
            if let layout = tryLayout(cells, fontSize: size, pitch: size * pitchFactor, area: area, style: style,
                                      isVertical: isVertical, font: font) {
                // A slightly smaller size is better than a break inside a word or a last
                // column of one character.
                let flaws = Self.flaws(of: layout, cells: cells)
                if flaws < (best?.flaws ?? .max) { best = (layout, flaws) }
                if flaws == 0 { return layout }
            }
            if let best, size < best.layout.fontSize * 0.88 { return best.layout }
            size *= step
        }
        if let best { return best.layout }
        return overflowing(cells, fontSize: smallest, pitch: smallest * pitchFactor, area: area,
                           isVertical: isVertical, font: fontAt(smallest))
    }

    /// Breaks inside a word, and a last line that holds one character beside its punctuation.
    private static func flaws(of layout: TextLayout, cells: [TextCell]) -> Int {
        var flaws = layout.lines.dropLast().filter { cells[$0.cells.upperBound - 1].breakQuality == 0 }.count
        if layout.lines.count > 1, let last = layout.lines.last,
           cells[last.cells].filter({ !$0.cannotStart && !$0.cannotEnd }).count <= 1 {
            flaws += 1
        }
        return flaws
    }

    /// One to n columns at the original column pitch, centred on the old text or moved by
    /// half or a whole pitch; the first arrangement that holds the text.
    func tryLayout(
        _ cells: [TextCell], fontSize: Double, pitch: Double, area: LayoutArea, style: TextStyle,
        isVertical: Bool, font: CTFont
    ) -> TextLayout? {
        let advances = cells.map { advance($0, font: font, fontSize: fontSize, isVertical: isVertical) }
        let rect = area.mask.rect
        let crossExtent = Double(isVertical ? rect.width : rect.height)
        let maximumLines = max(1, Int((crossExtent - fontSize) / pitch) + 1)
        let anchorX = Double(area.anchor.x), anchorY = Double(area.anchor.y)
        let half = isVertical ? fontSize * 0.5 : fontSize * 0.62
        for count in 1...maximumLines {
            for shift in [0.0, 0.5, -0.5, 1.0, -1.0] {
                let centres = (0..<count).map { line -> Double in
                    let offset = Double(count - 1) / 2 - Double(line)
                    return isVertical ? anchorX + (shift + offset) * pitch : anchorY + (shift - offset) * pitch
                }
                let spans = centres.map {
                    area.span(across: $0 - half, $0 + half, near: isVertical ? anchorY : anchorX, isVertical: isVertical)
                }
                let capacities = spans.map { $0.end - $0.start }
                if capacities.contains(where: { $0 < fontSize }) { continue }
                guard let ranges = LineBreaker.breakLines(cells, advances: advances, capacities: capacities) else {
                    continue
                }
                let lengths = ranges.map { advances[$0].reduce(0, +) }
                let lines = place(ranges: ranges, lengths: lengths, centres: centres, spans: spans,
                                  alignment: style.alignment, anchor: isVertical ? anchorY : anchorX)
                return TextLayout(cells: cells, fontSize: fontSize, isVertical: isVertical, lines: lines, overflows: false)
            }
        }
        return nil
    }

    /// Columns that start together when one start suits them all, as letterers set them;
    /// otherwise each is moved only as far as the area's outline forces it.
    func place(
        ranges: [Range<Int>], lengths: [Double], centres: [Double], spans: [(start: Double, end: Double)],
        alignment: TextAlignment, anchor: Double
    ) -> [PlacedLine] {
        let count = ranges.count
        let used = Array(centres.prefix(count))
        // Fewer columns than planned: centre the ones that were needed.
        var offset = 0.0
        if count < centres.count, let first = centres.first, let last = centres.last,
           let usedFirst = used.first, let usedLast = used.last {
            offset = ((first + last) - (usedFirst + usedLast)) / 2
        }
        let longest = lengths.max() ?? 0
        if alignment == .start {
            let low = spans.prefix(count).map(\.start).max() ?? 0
            let high = zip(spans.prefix(count), lengths).map { $0.end - $1 }.min() ?? 0
            if low <= high {
                let start = min(max(anchor - longest / 2, low), high)
                return (0..<count).map {
                    PlacedLine(cells: ranges[$0], centre: used[$0] + offset, start: start, length: lengths[$0])
                }
            }
        }
        let common = anchor - longest / 2
        return (0..<count).map { line in
            let wanted = alignment == .center ? anchor - lengths[line] / 2 : common
            let start = min(max(wanted, spans[line].start), spans[line].end - lengths[line])
            return PlacedLine(cells: ranges[line], centre: used[line] + offset, start: start, length: lengths[line])
        }
    }

    /// Text that fits at no size: the smallest size, as many columns as the area's box takes,
    /// running over its shape.
    private func overflowing(
        _ cells: [TextCell], fontSize: Double, pitch: Double, area: LayoutArea, isVertical: Bool, font: CTFont
    ) -> TextLayout {
        let advances = cells.map { advance($0, font: font, fontSize: fontSize, isVertical: isVertical) }
        let rect = area.mask.rect
        let capacity = max(fontSize, Double(isVertical ? rect.height : rect.width) * 0.9)
        let ranges = LineBreaker.greedy(cells, advances, Array(repeating: capacity, count: 40), target: capacity)
            ?? [0..<cells.count]
        let count = ranges.count
        let lines = ranges.enumerated().map { index, range -> PlacedLine in
            let length = advances[range].reduce(0, +)
            let offset = (Double(count - 1) / 2 - Double(index)) * pitch
            let centre = isVertical ? Double(area.anchor.x) + offset : Double(area.anchor.y) - offset
            let start = (isVertical ? Double(area.anchor.y) : Double(area.anchor.x)) - length / 2
            return PlacedLine(cells: range, centre: centre, start: start, length: length)
        }
        return TextLayout(cells: cells, fontSize: fontSize, isVertical: isVertical, lines: lines, overflows: true)
    }
}
