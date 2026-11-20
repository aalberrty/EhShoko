import CoreFoundation
import Foundation

/// One unit of a set line: a character, two marks or digits that share a square, or a run of
/// Latin letters set sideways.
struct TextCell: Sendable, Equatable {
    enum Form: Sendable, Equatable {
        /// Upright in its own square.
        case upright
        /// Set horizontally inside one square of a vertical column (縦中横): `!?` and numbers
        /// of one or two digits.
        case tateChuYoko
        /// Turned a quarter, running down the column: longer Latin words and numbers.
        case sideways
    }

    var text: String
    var form: Form
    /// Closing punctuation: never first in a column.
    var cannotStart = false
    /// Opening punctuation: never last in a column.
    var cannotEnd = false
    /// `……` and `——` stay together.
    var gluedToNext = false
    /// How good a break after this cell is: 0 inside a word, 1 at a word's end, 2 after
    /// punctuation.
    var breakQuality = 0
}

enum CellBuilder {
    static let closing: Set<Character> = Set("，。、．：；！？）」』》〉】〕｝…‥ー～・,.:;!?)]}%")
    static let opening: Set<Character> = Set("（「『《〈【〔｛([{")
    static let strongBreak: Set<Character> = Set("，。、！？；：…」』）")
    private static let marks = "!?！？"

    /// Prepares translated text for Chinese lettering and cuts it into cells.
    static func cells(_ raw: String, isVertical: Bool) -> [TextCell] {
        var text = raw.replacingOccurrences(of: "...", with: "…").replacingOccurrences(of: "・・", with: "…")
            .replacingOccurrences(of: "\n", with: "")
        if isVertical {
            // Vertical Simplified Chinese uses corner brackets for quotation marks.
            for (from, to) in [("“", "「"), ("”", "」"), ("‘", "『"), ("’", "』"), ("~", "～"), ("〜", "～")] {
                text = text.replacingOccurrences(of: from, with: to)
            }
        }
        let characters = Array(text)
        var cells: [TextCell] = []
        var index = 0
        while index < characters.count {
            let character = characters[index]
            if character == " " {
                index += 1
            } else if isVertical, marks.contains(character) {
                var end = index
                while end < characters.count, marks.contains(characters[end]) { end += 1 }
                cells += markCells(characters[index..<end].map(halfWidth))
                index = end
            } else if isVertical, isLatinOrDigit(character) {
                var end = index
                while end < characters.count, isLatinOrDigit(characters[end]) { end += 1 }
                let run = String(characters[index..<end])
                cells.append(TextCell(text: run, form: run.count <= 2 ? .tateChuYoko : .sideways))
                index = end
            } else {
                var cell = TextCell(text: String(character), form: .upright)
                cell.cannotStart = closing.contains(character)
                cell.cannotEnd = opening.contains(character)
                let next = index + 1 < characters.count ? characters[index + 1] : nil
                cell.gluedToNext = (character == "…" || character == "—") && next == character
                cells.append(cell)
                index += 1
            }
        }
        markBreaks(&cells)
        return cells
    }

    /// A run of `!` and `?` in a vertical column: two marks share one square, a single mark
    /// takes its full-width form.
    private static func markCells(_ run: [Character]) -> [TextCell] {
        var cells: [TextCell] = []
        var index = 0
        while index < run.count {
            if index + 1 < run.count {
                cells.append(TextCell(text: String(run[index...(index + 1)]), form: .tateChuYoko, cannotStart: true))
                index += 2
            } else {
                cells.append(TextCell(text: String(fullWidth(run[index])), form: .upright, cannotStart: true))
                index += 1
            }
        }
        return cells
    }

    /// Marks where words end, with the system's Chinese word segmentation, and where
    /// punctuation makes a break a good one.
    private static func markBreaks(_ cells: inout [TextCell]) {
        let joined = cells.map(\.text).joined() as CFString
        var wordEnds = Set<Int>()
        let tokenizer = CFStringTokenizerCreate(
            nil, joined, CFRange(location: 0, length: CFStringGetLength(joined)),
            kCFStringTokenizerUnitWordBoundary, Locale(identifier: "zh-Hans") as CFLocale
        )
        while !CFStringTokenizerAdvanceToNextToken(tokenizer).isEmpty {
            let range = CFStringTokenizerGetCurrentTokenRange(tokenizer)
            wordEnds.insert(range.location + range.length)
        }
        var offset = 0
        for index in cells.indices {
            offset += cells[index].text.utf16.count
            let endsStrongly = cells[index].text.last.map(strongBreak.contains) ?? false
            if endsStrongly || (cells[index].form == .tateChuYoko && cells[index].cannotStart) {
                cells[index].breakQuality = 2
            } else if wordEnds.contains(offset) {
                cells[index].breakQuality = 1
            }
        }
    }

    private static func isLatinOrDigit(_ character: Character) -> Bool {
        character.isASCII && (character.isLetter || character.isNumber)
    }

    private static func halfWidth(_ character: Character) -> Character {
        character == "！" ? "!" : character == "？" ? "?" : character
    }

    private static func fullWidth(_ character: Character) -> Character {
        character == "!" ? "！" : character == "?" ? "？" : character
    }

    /// Whether a column may end after `cells[index - 1]` and the next start at `cells[index]`.
    static func canBreak(_ cells: [TextCell], at index: Int) -> Bool {
        if index <= 0 || index >= cells.count { return true }
        return !cells[index].cannotStart && !cells[index - 1].cannotEnd && !cells[index - 1].gluedToNext
    }
}

/// Cuts cells into columns that fit given lengths, keeping the columns balanced and breaking
/// after punctuation or at a word's end when that costs little.
enum LineBreaker {
    /// The cells of each column, or `nil` when they do not fit `capacities`.
    static func breakLines(_ cells: [TextCell], advances: [Double], capacities: [Double]) -> [Range<Int>]? {
        let total = advances.reduce(0, +)
        guard !cells.isEmpty, let longest = capacities.max(), longest > 0 else { return nil }
        // Longer and longer targets: the first that works gives the most even columns.
        var target = total / Double(capacities.count)
        while target <= longest + 0.001 {
            if let ranges = greedy(cells, advances, capacities, target: target) { return ranges }
            target += max(1, total * 0.02)
        }
        return greedy(cells, advances, capacities, target: longest)
    }

    /// Fills each column up to `target` (and its own capacity), then steps back to the best
    /// place to break.
    static func greedy(_ cells: [TextCell], _ advances: [Double], _ capacities: [Double], target: Double) -> [Range<Int>]? {
        var ranges: [Range<Int>] = []
        var start = 0
        for capacity in capacities {
            if start >= cells.count { break }
            let limit = min(capacity, target * 1.08)
            var length = 0.0, end = start
            var lengths: [Double] = []
            while end < cells.count, length + advances[end] <= limit + 0.001 {
                length += advances[end]
                lengths.append(length)
                end += 1
            }
            if end == start { return nil }
            if end < cells.count {
                // The best break in the last part of the column: after punctuation, then at a
                // word's end, then anywhere the rules allow.
                var best = -1, bestScore = -1.0
                for index in stride(from: end, to: start, by: -1) where CellBuilder.canBreak(cells, at: index) {
                    let filled = lengths[index - start - 1] / limit
                    if filled < 0.55 { break }
                    let score = Double(cells[index - 1].breakQuality) * 0.5 + filled
                    if score > bestScore {
                        bestScore = score
                        best = index
                    }
                }
                if best < 0 { return nil }
                end = best
            }
            ranges.append(start..<end)
            start = end
        }
        return start >= cells.count ? ranges : nil
    }
}
