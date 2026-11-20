import Compression
import CoreGraphics
@testable import EhPageTranslation
import EhModels
import Foundation

/// The research's files the opt-in drawing tests read: the default detector's reference
/// output for a page, as the blocks the pipeline will hand to drawing, and the truth.
enum ResearchReferences {
    static let pages = "research/mt-spike/ocr/pages"
    static let truth = "research/mt-det/truth"
    static let detections = "models/det-phone/k2xl/mac_ref768.json"
    static let masks = "models/det-phone/k2xl/ref768"
    static let translations = "research/mt-jmt/ref/swift-cpu.json"

    /// One item of a page's truth: what kind of text it is and where.
    struct TruthItem: Decodable {
        let type: String
        let box: [Double]
        let text: String?

        var rect: PixelRect {
            PixelRect(x0: Int(box[0].rounded()), y0: Int(box[1].rounded()), x1: Int(box[2].rounded()), y1: Int(box[3].rounded()))
        }
    }

    struct Truth: Decodable {
        let page: String
        let size: [Int]
        let items: [TruthItem]
    }

    private struct Detections: Decodable {
        /// For each page, rows of x0, y0, x1, y1 (in thousandths of the page), score, class
        /// (0 text, 1 sound effect, 2 balloon, 3 panel) and the query's number.
        let pages: [String: [[Double]]]
    }

    private struct Translations: Decodable {
        struct Line: Decodable {
            let ja: String
            let zh: String
        }

        struct Page: Decodable {
            let page: String
            let lines: [Line]
        }

        let pages: [Page]
    }

    static func truth(of page: String, in folder: PrivateFolder) throws -> Truth {
        try JSONDecoder().decode(Truth.self, from: Data(contentsOf: folder.url("\(truth)/\(page).json")))
    }

    /// The names of the test pages whose picture is in the folder.
    static func pageNames(in folder: PrivateFolder) throws -> [String] {
        try folder.files(in: pages, withExtensions: ["png"]).map { $0.deletingPathExtension().lastPathComponent }
    }

    static func bitmap(of page: String, in folder: PrivateFolder) throws -> PageBitmap {
        try PageBitmap(data: Data(contentsOf: folder.url("\(pages)/\(page).png")))
    }

    /// The reference detections of `page` as blocks: text boxes after the removal of
    /// duplicates, each with the balloon whose mask holds its centre. With `withMasks` false
    /// a balloon carries its box alone, as a page drawn again from its stored text does.
    ///
    /// The detector calls about a fifth of the dialogue it finds a sound effect. With
    /// `includingSoundEffects` those boxes are blocks too, of the kind `.soundEffect`: the
    /// research counted them when it measured how much ink the detector's masks cover.
    static func blocks(
        of page: String, bitmap: PageBitmap, in folder: PrivateFolder, withMasks: Bool,
        includingSoundEffects: Bool = false
    ) throws -> [TextBlock] {
        let all = try JSONDecoder().decode(Detections.self, from: Data(contentsOf: folder.url(detections)))
        let rows = all.pages[page] ?? []
        let width = Double(bitmap.width), height = Double(bitmap.height)
        func box(_ row: [Double]) -> CGRect {
            CGRect(x: row[0] * width / 1000, y: row[1] * height / 1000, width: (row[2] - row[0]) * width / 1000,
                   height: (row[3] - row[1]) * height / 1000)
                .intersection(CGRect(x: 0, y: 0, width: width, height: height))
        }
        let logits = try MaskLogits(url: folder.url("\(masks)/\(page).npz"))
        var balloons: [Balloon] = []
        for (index, row) in rows.enumerated() where Int(row[5]) == 2 {
            let rect = box(row)
            balloons.append(Balloon(box: rect, mask: logits.mask(index, in: PixelRect(covering: rect), bitmap: bitmap)))
        }
        // Text and sound effects compete: of two boxes that overlap by 0.6 or more, the one
        // with the higher score stays.
        var kept: [[Double]] = []
        for row in rows.filter({ Int($0[5]) <= 1 }).sorted(by: { $0[4] > $1[4] }) {
            let candidate = box(row)
            let duplicate = kept.contains { other in
                let shared = box(other).intersection(candidate)
                guard !shared.isNull else { return false }
                let overlap = shared.width * shared.height
                let union = box(other).width * box(other).height + candidate.width * candidate.height - overlap
                return overlap / max(1, union) >= 0.6
            }
            if !duplicate { kept.append(row) }
        }
        return kept.filter { includingSoundEffects || Int($0[5]) == 0 }.map { row in
            let rect = box(row)
            let centre = (Int(rect.midX), Int(rect.midY))
            let balloon = balloons.first { $0.mask?.contains(centre.0, centre.1) ?? false }
            let kind: RegionKind = Int(row[5]) == 1 ? .soundEffect : (balloon == nil ? .aside : .dialogue)
            return TextBlock(
                box: rect, kind: kind, isVertical: rect.height > rect.width, score: Float(row[4]),
                balloon: balloon.map { withMasks ? $0 : Balloon(box: $0.box) }
            )
        }
    }

    /// Gives each block the Japanese of the truth item it lies on, standing in for the reader,
    /// and with `translations` (Japanese without spaces to Chinese) its Chinese. Where the
    /// detector cut one item into several boxes, the item's text is shared out among them by
    /// their size, in reading order.
    ///
    /// - Returns: how many blocks got `filler` cut to length instead of a translation,
    ///   because the research translated no such line.
    @discardableResult
    static func assignText(
        to blocks: inout [TextBlock], truth: Truth, translations: [String: String] = [:], filler: [Character] = []
    ) -> Int {
        let items = truth.items.filter { $0.type == "bubble" || $0.type == "free" }
        var members = [[Int]](repeating: [], count: items.count)
        for (index, block) in blocks.enumerated() {
            let box = PixelRect(covering: block.box)
            guard let best = items.indices.max(by: { items[$0].rect.intersection(box).area < items[$1].rect.intersection(box).area }),
                  items[best].rect.intersection(box).area > 0
            else { continue }
            members[best].append(index)
        }
        var standIns = 0
        for (item, indices) in zip(items, members) where !indices.isEmpty {
            let source = Array(item.text ?? "")
            let known = translations[normalised(item.text ?? "")].map(Array.init)
            // Columns are read from the right.
            let ordered = indices.sorted { blocks[$0].box.midX > blocks[$1].box.midX }
            let total = ordered.reduce(0.0) { $0 + Double(blocks[$1].box.width * blocks[$1].box.height) }
            var seen = 0.0
            for index in ordered {
                let from = seen / max(1, total)
                seen += Double(blocks[index].box.width * blocks[index].box.height)
                let to = seen / max(1, total)
                func part(_ text: [Character]) -> String {
                    String(text[Int((Double(text.count) * from).rounded())..<Int((Double(text.count) * to).rounded())])
                }
                blocks[index].source = part(source)
                if let known, !known.isEmpty {
                    blocks[index].translation = part(known)
                } else if !filler.isEmpty {
                    let length = max(2, min(filler.count, part(source).count * 4 / 5))
                    blocks[index].translation = String(filler.prefix(length))
                    standIns += 1
                }
            }
        }
        return standIns
    }

    /// The default translator's Chinese for each line of `page` the research translated, by
    /// its Japanese without spaces.
    static func translations(of page: String, in folder: PrivateFolder) throws -> [String: String] {
        let all = try JSONDecoder().decode(Translations.self, from: Data(contentsOf: folder.url(translations)))
        var out: [String: String] = [:]
        for line in all.pages.first(where: { $0.page == page })?.lines ?? [] { out[normalised(line.ja)] = line.zh }
        return out
    }

    static func normalised(_ text: String) -> String {
        text.precomposedStringWithCompatibilityMapping.filter { !$0.isWhitespace }
    }
}

/// The mask logits the reference run kept for a page: one 192 × 192 plane for each detection,
/// in a NumPy archive.
struct MaskLogits {
    let count: Int
    let side: Int
    private let values: [Float]

    init(url: URL) throws {
        let archive = try Data(contentsOf: url)
        let array = try Self.firstEntry(of: archive)
        // A NumPy file: magic, version, the length of a header that gives the shape, then
        // the values.
        guard array.count > 10, array.prefix(6) == Data([0x93, 0x4E, 0x55, 0x4D, 0x50, 0x59]) else { throw Malformed() }
        let headerLength = Int(array[8]) | Int(array[9]) << 8
        let header = String(decoding: array[10..<(10 + headerLength)], as: UTF8.self)
        guard header.contains("'<f2'"), let open = header.range(of: "'shape': ("),
              let close = header[open.upperBound...].firstIndex(of: ")")
        else { throw Malformed() }
        let shape = header[open.upperBound..<close].split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        guard shape.count == 3, shape[1] == shape[2] else { throw Malformed() }
        let total = shape[0] * shape[1] * shape[1]
        let body = array.dropFirst(10 + headerLength)
        guard body.count == total * 2 else { throw Malformed() }
        count = shape[0]
        side = shape[1]
        values = body.withUnsafeBytes { raw in
            (0..<total).map { Half.toFloat(raw.loadUnaligned(fromByteOffset: $0 * 2, as: UInt16.self)) }
        }
    }

    struct Malformed: Error {}

    /// The first file of a zip archive, inflated.
    private static func firstEntry(of archive: Data) throws -> Data {
        func u16(_ offset: Int) -> Int { Int(archive[offset]) | Int(archive[offset + 1]) << 8 }
        func u32(_ offset: Int) -> Int { u16(offset) | u16(offset + 2) << 16 }
        // The directory at the archive's end has the sizes; the local header only says where
        // the data starts.
        guard let end = (0...(archive.count - 22)).reversed().first(where: { u32($0) == 0x0605_4B50 }) else { throw Malformed() }
        let directory = u32(end + 16)
        guard u32(directory) == 0x0201_4B50 else { throw Malformed() }
        let method = u16(directory + 10), compressed = u32(directory + 20), size = u32(directory + 24)
        let local = u32(directory + 42)
        let start = local + 30 + u16(local + 26) + u16(local + 28)
        let body = archive.subdata(in: start..<(start + compressed))
        if method == 0 { return body }
        guard method == 8 else { throw Malformed() }
        var out = Data(count: size)
        let written = out.withUnsafeMutableBytes { destination in
            body.withUnsafeBytes { source in
                compression_decode_buffer(
                    destination.bindMemory(to: UInt8.self).baseAddress!, size,
                    source.bindMemory(to: UInt8.self).baseAddress!, compressed, nil, COMPRESSION_ZLIB
                )
            }
        }
        guard written == size else { throw Malformed() }
        return out
    }

    /// Detection `index`'s mask inside `rect`, in page pixels: the logits sampled bilinearly
    /// (the model's input is the page stretched to a square) and cut at zero.
    func mask(_ index: Int, in rect: PixelRect, bitmap: PageBitmap) -> RegionMask? {
        let rect = rect.insetBy(-4, -4).clamped(width: bitmap.width, height: bitmap.height)
        guard index < count, !rect.isEmpty else { return nil }
        let base = index * side * side
        func sample(_ position: Int, _ extent: Int) -> (Int, Int, Float) {
            let value = min(max((Float(position) + 0.5) * Float(side) / Float(extent) - 0.5, 0), Float(side - 1))
            let low = Int(value)
            return (low, min(low + 1, side - 1), value - Float(low))
        }
        var bits = [UInt8](repeating: 0, count: rect.area)
        for y in rect.y0..<rect.y1 {
            let (y0, y1, fy) = sample(y, bitmap.height)
            for x in rect.x0..<rect.x1 {
                let (x0, x1, fx) = sample(x, bitmap.width)
                let top = values[base + y0 * side + x0] * (1 - fx) + values[base + y0 * side + x1] * fx
                let bottom = values[base + y1 * side + x0] * (1 - fx) + values[base + y1 * side + x1] * fx
                if top * (1 - fy) + bottom * fy > 0 { bits[(y - rect.y0) * rect.width + x - rect.x0] = 1 }
            }
        }
        return RegionMask(rect: rect, bits: bits)
    }
}

/// The glyph pixels of a truth item, found as the detector research found them: Otsu's split
/// inside the box grown by six pixels, pieces that touch the grown box's edge dropped
/// (balloon outlines and artwork running through), and the smaller of the two classes kept.
enum TruthInk {
    static func mask(of item: PixelRect, bitmap: PageBitmap, pad: Int = 6) -> RegionMask? {
        let grown = item.insetBy(-pad, -pad).clamped(width: bitmap.width, height: bitmap.height)
        guard !grown.isEmpty else { return nil }
        let window = PixelWindow(page: bitmap, rect: grown)
        let width = window.width, height = window.height
        // OpenCV's grey: 0.299 R + 0.587 G + 0.114 B.
        let grey = (0..<window.count).map { index -> UInt8 in
            let color = window.color(index)
            let red = 0.299 * Double(color.red), green = 0.587 * Double(color.green), blue = 0.114 * Double(color.blue)
            return UInt8((red + green + blue).rounded())
        }
        var histogram = [Int](repeating: 0, count: 256)
        for value in grey { histogram[Int(value)] += 1 }
        let threshold = Otsu.threshold(histogram)
        let inner = window.local(item)
        func interior(_ plane: [UInt8]) -> [UInt8] {
            var kept = [UInt8](repeating: 0, count: plane.count)
            for component in Morphology.components(plane, width: width, height: height) {
                let bounds = component.bounds
                if bounds.x0 == 0 || bounds.y0 == 0 || bounds.x1 >= width || bounds.y1 >= height { continue }
                for pixel in component.pixels { kept[Int(pixel)] = 1 }
            }
            return kept
        }
        let dark = interior(grey.map { Int($0) <= threshold ? 1 : 0 })
        let light = interior(grey.map { Int($0) > threshold ? 1 : 0 })
        let candidates = [dark, light].filter { Double(Morphology.count($0)) >= 0.005 * Double(inner.area) }
        if let ink = candidates.min(by: { Morphology.count($0) < Morphology.count($1) }) {
            return RegionMask(plane: ink, in: window)
        }
        // Nothing clear of the edge: the class that differs from the border, inside the box.
        var border: [UInt8] = []
        for x in 0..<width { border += [grey[x], grey[(height - 1) * width + x]] }
        for y in 0..<height { border += [grey[y * width], grey[y * width + width - 1]] }
        let borderIsDark = Int(border.sorted()[border.count / 2]) <= threshold
        var ink = [UInt8](repeating: 0, count: window.count)
        for y in inner.y0..<inner.y1 {
            for x in inner.x0..<inner.x1 where (Int(grey[y * width + x]) > threshold) == borderIsDark {
                ink[y * width + x] = 1
            }
        }
        return RegionMask(plane: ink, in: window)
    }
}
