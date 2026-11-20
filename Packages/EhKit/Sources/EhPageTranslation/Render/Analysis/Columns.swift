/// One column of a block of vertical text, or one row of horizontal text.
struct TextColumn: Sendable, Equatable {
    /// The bounds of the column's ink, in page pixels.
    var rect: PixelRect
    /// Furigana beside a column: erased with it, but neither measured nor counted.
    var isRuby = false
}

/// The columns of one block in reading order: right to left when vertical, top to bottom
/// otherwise.
struct BlockColumns: Sendable, Equatable {
    var isVertical: Bool
    var columns: [TextColumn]

    /// The columns without furigana.
    var base: [TextColumn] { columns.filter { !$0.isRuby } }

    /// The size of a glyph across the columns: the median thickness of the base columns.
    var glyphSize: Double? {
        let sizes = base.map { Double(isVertical ? $0.rect.width : $0.rect.height) }.sorted()
        return sizes.isEmpty ? nil : sizes[sizes.count / 2]
    }
}

/// Finds the columns of a block from its ink. The detector gives one box for a block and says
/// nothing of its lines, and the measures of size, pitch and alignment need them.
///
/// Ink is projected across the columns; stretches with ink are columns and stretches without
/// are the gaps between them. Two things spoil that, and the number of characters the reader
/// found settles both: a glyph such as い or 川 has a gap of its own, and tightly set columns
/// have none between them.
enum Columns {
    /// - Parameters:
    ///   - ink: the block's ink as a plane the size of the scene's window.
    ///   - prefersVertical: the detector's guess, which decides when the ink does not.
    ///   - cellCount: how many character cells the block's text takes; 0 when unknown.
    static func find(ink: [UInt8], scene: BlockScene, prefersVertical: Bool, cellCount: Int) -> BlockColumns {
        let window = scene.window
        guard let bounds = inkBounds(ink, window: window, within: InkMask.searchRect(scene)) else {
            return BlockColumns(isVertical: prefersVertical, columns: [])
        }
        let across = profile(ink, window: window, bounds: bounds, alongX: true)
        let down = profile(ink, window: window, bounds: bounds, alongX: false)
        let isVertical = decideVertical(
            across: across, down: down, bounds: bounds, prefersVertical: prefersVertical, cellCount: cellCount
        )
        let counts = isVertical ? across : down
        let length = isVertical ? bounds.height : bounds.width
        var spans = runs(counts, minimumGap: 1)
        if let glyph = expectedGlyphSize(extent: counts.count, length: length, cellCount: cellCount) {
            spans = merge(spans, limit: 1.2 * glyph)
            spans = spans.flatMap { split($0, counts: counts, glyph: glyph) }
            // There are never more columns than characters.
            spans = merge(spans, downTo: cellCount)
        }
        var columns = spans.compactMap { span -> TextColumn? in
            let rect = isVertical
                ? PixelRect(x0: bounds.x0 + span.lowerBound, y0: bounds.y0, x1: bounds.x0 + span.upperBound, y1: bounds.y1)
                : PixelRect(x0: bounds.x0, y0: bounds.y0 + span.lowerBound, x1: bounds.x1, y1: bounds.y0 + span.upperBound)
            return inkBounds(ink, window: window, within: rect).map { TextColumn(rect: $0) }
        }
        if isVertical {
            markRuby(&columns)
            columns.reverse()
        }
        return BlockColumns(isVertical: isVertical, columns: columns)
    }

    /// The number of cells a text takes when set: one for each character, one for a pair of
    /// `!` and `?`, none for spaces.
    static func cellCount(of text: String) -> Int {
        var count = 0, marks = 0
        for character in text where !character.isWhitespace {
            if "!?！？".contains(character) {
                marks += 1
                if marks % 2 == 1 { count += 1 }
            } else {
                marks = 0
                count += 1
            }
        }
        return count
    }

    // MARK: Projections

    /// The smallest rectangle, in page pixels, around the ink inside `rect` (the whole window
    /// when `nil`).
    static func inkBounds(_ ink: [UInt8], window: PixelWindow, within rect: PixelRect? = nil) -> PixelRect? {
        let area = rect.map { window.local($0) } ?? PixelRect(x0: 0, y0: 0, x1: window.width, y1: window.height)
        var x0 = area.x1, y0 = area.y1, x1 = area.x0, y1 = area.y0
        for y in area.y0..<area.y1 {
            let row = y * window.width
            for x in area.x0..<area.x1 where ink[row + x] != 0 {
                if x < x0 { x0 = x }
                if x >= x1 { x1 = x + 1 }
                if y < y0 { y0 = y }
                y1 = y + 1
            }
        }
        guard x1 > x0, y1 > y0 else { return nil }
        let origin = window.rect
        return PixelRect(x0: x0 + origin.x0, y0: y0 + origin.y0, x1: x1 + origin.x0, y1: y1 + origin.y0)
    }

    /// The number of ink pixels in each column (`alongX`) or row of `bounds`.
    private static func profile(_ ink: [UInt8], window: PixelWindow, bounds: PixelRect, alongX: Bool) -> [Int] {
        let local = window.local(bounds)
        var counts = [Int](repeating: 0, count: alongX ? local.width : local.height)
        for y in local.y0..<local.y1 {
            let row = y * window.width
            for x in local.x0..<local.x1 where ink[row + x] != 0 {
                counts[alongX ? x - local.x0 : y - local.y0] += 1
            }
        }
        return counts
    }

    /// The stretches of `counts` that hold ink, joined across gaps shorter than `minimumGap`.
    static func runs(_ counts: [Int], minimumGap: Int) -> [Range<Int>] {
        var out: [Range<Int>] = []
        var start: Int?
        for index in 0...counts.count {
            let inked = index < counts.count && counts[index] > 0
            if inked, start == nil { start = index }
            if !inked, let from = start {
                if let last = out.last, from - last.upperBound < minimumGap {
                    out[out.count - 1] = last.lowerBound..<index
                } else {
                    out.append(from..<index)
                }
                start = nil
            }
        }
        return out
    }

    // MARK: Direction

    /// Whether the text runs in columns. Gaps between lines are wider than gaps between
    /// characters, and lines are longer than they are thick; where the ink says neither, the
    /// detector's guess stands.
    private static func decideVertical(
        across: [Int], down: [Int], bounds: PixelRect, prefersVertical: Bool, cellCount: Int
    ) -> Bool {
        let gap = max(2, min(bounds.width, bounds.height) * 8 / 100)
        let columns = runs(across, minimumGap: gap), rows = runs(down, minimumGap: gap)
        // Lines of one character each are no lines: as many rows as characters are one
        // column, and as many columns as characters are one row.
        if cellCount > 0 {
            let singleRows = rows.count > 1 && cellCount * 2 < rows.count * 3
            let singleColumns = columns.count > 1 && cellCount * 2 < columns.count * 3
            if singleRows, !singleColumns { return true }
            if singleColumns, !singleRows { return prefersVertical }
        }
        func medianLength(_ spans: [Range<Int>]) -> Int { spans.map(\.count).sorted()[spans.count / 2] }
        func meanGap(_ spans: [Range<Int>]) -> Double {
            let total = zip(spans, spans.dropFirst()).reduce(0) { $0 + $1.1.lowerBound - $1.0.upperBound }
            return Double(total) / Double(max(1, spans.count - 1))
        }
        switch (columns.count > 1, rows.count > 1) {
        case (true, false):
            // Several columns, or one row of separate characters.
            return bounds.height * 2 >= medianLength(columns) * 3 || prefersVertical
        case (false, true):
            // Several rows, or one column of separate characters.
            return !(bounds.width >= medianLength(rows) * 2)
        case (true, true):
            let columnGap = meanGap(columns), rowGap = meanGap(rows)
            if columnGap > rowGap * 1.3 { return true }
            if rowGap > columnGap * 1.3 { return false }
            return prefersVertical
        case (false, false):
            return prefersVertical
        }
    }

    // MARK: Glyph size from the text

    /// The thickness one column should have, from the block's shape and its number of cells:
    /// the number of columns that makes the cells square, and with it the share of the
    /// block's extent that one column takes. `nil` when the text is unknown.
    ///
    /// - Parameters:
    ///   - extent: the ink's size across the columns.
    ///   - length: the ink's size along them.
    static func expectedGlyphSize(extent: Int, length: Int, cellCount: Int) -> Double? {
        guard cellCount > 0, extent > 0, length > 0 else { return nil }
        // A column's ink is about 0.9 of a cell wide; columns stand about 1.3 cells apart.
        let inkShare = 0.9, linePitch = 1.3
        var best: (error: Double, columns: Int)?
        for count in 1...min(cellCount, 12) {
            let longest = (cellCount + count - 1) / count
            let cell = Double(length) / Double(longest)
            let predicted = (Double(count - 1) * linePitch + inkShare) * cell
            let ratio = predicted / Double(extent)
            let error = abs(ratio > 1 ? ratio - 1 : 1 / ratio - 1)
            if error < (best?.error ?? .infinity) { best = (error, count) }
        }
        guard let columns = best?.columns else { return nil }
        return Double(extent) * inkShare / (Double(columns - 1) * linePitch + inkShare)
    }

    /// Joins neighbouring stretches while the joined stretch is still no thicker than `limit`:
    /// the parts of a glyph with a gap of its own.
    private static func merge(_ spans: [Range<Int>], limit: Double) -> [Range<Int>] {
        var out: [Range<Int>] = []
        for span in spans {
            if let last = out.last, Double(span.upperBound - last.lowerBound) <= limit {
                out[out.count - 1] = last.lowerBound..<span.upperBound
            } else {
                out.append(span)
            }
        }
        return out
    }

    /// Joins the two neighbouring stretches with the smallest gap between them, again and
    /// again, until at most `count` are left.
    private static func merge(_ spans: [Range<Int>], downTo count: Int) -> [Range<Int>] {
        var out = spans
        while out.count > max(1, count) {
            guard let nearest = (1..<out.count).min(by: {
                out[$0].lowerBound - out[$0 - 1].upperBound < out[$1].lowerBound - out[$1 - 1].upperBound
            }) else { break }
            out[nearest - 1] = out[nearest - 1].lowerBound..<out[nearest].upperBound
            out.remove(at: nearest)
        }
        return out
    }

    /// Cuts a stretch that is several glyphs thick at the thinnest places of its profile:
    /// columns set too tightly to leave a gap.
    private static func split(_ span: Range<Int>, counts: [Int], glyph: Double) -> [Range<Int>] {
        let parts = Int((Double(span.count) / (1.25 * glyph)).rounded())
        guard parts >= 2, Double(span.count) >= 1.75 * glyph else { return [span] }
        var cuts: [Int] = []
        let reach = max(1, Int(glyph * 0.3))
        for part in 1..<parts {
            let ideal = span.lowerBound + span.count * part / parts
            let candidates = max(span.lowerBound + 1, ideal - reach)...min(span.upperBound - 1, ideal + reach)
            guard let cut = candidates.min(by: { counts[$0] < counts[$1] }) else { continue }
            cuts.append(cut)
        }
        var out: [Range<Int>] = []
        var start = span.lowerBound
        for cut in cuts where cut > start {
            out.append(start..<cut)
            start = cut
        }
        out.append(start..<span.upperBound)
        return out
    }

    // MARK: Furigana

    /// Marks furigana: a narrow column standing close to the right of a wider one, beside it
    /// for most of its own length. `columns` are in order from left to right.
    private static func markRuby(_ columns: inout [TextColumn]) {
        guard columns.count > 1 else { return }
        for index in 1..<columns.count {
            let base = columns[index - 1].rect, ruby = columns[index].rect
            guard !columns[index - 1].isRuby, ruby.width * 100 <= base.width * 55 else { continue }
            let gap = ruby.x0 - base.x1
            let overlap = min(ruby.y1, base.y1) - max(ruby.y0, base.y0)
            if gap * 4 <= base.width, overlap * 2 > ruby.height { columns[index].isRuby = true }
        }
    }
}
