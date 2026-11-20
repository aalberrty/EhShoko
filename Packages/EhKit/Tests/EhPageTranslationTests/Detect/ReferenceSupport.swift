import Compression
import CoreML
@testable import EhPageTranslation
import Foundation
import Testing

/// What the opt-in tests need to compare with the research: compiled models, its box matching,
/// and its `.npz` files.
enum ReferenceSupport {
    /// The model package at `path` in the private folder, compiled once into the temporary
    /// folder and reused by later runs.
    static func compiledModel(_ path: String) async throws -> URL {
        let package = try PrivateFolder.required().url(path)
        let cache = FileManager.default.temporaryDirectory.appending(path: "EhPageTranslationTests-models", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        let name = path.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: ".mlpackage", with: ".mlmodelc")
        let compiled = cache.appending(path: name, directoryHint: .isDirectory)
        if FileManager.default.fileExists(atPath: compiled.path) { return compiled }
        let temporary = try await MLModel.compileModel(at: package)
        try? FileManager.default.removeItem(at: compiled)
        try FileManager.default.moveItem(at: temporary, to: compiled)
        return compiled
    }

    static func json(_ path: String) throws -> Any {
        try JSONSerialization.jsonObject(with: Data(contentsOf: PrivateFolder.required().url(path)))
    }

    static func page(_ path: String) throws -> PageBitmap {
        try PageBitmap(data: Data(contentsOf: PrivateFolder.required().url(path)))
    }

    /// The research's 18 test pages by name.
    static let pageNames = [
        "bl-10", "bl-11", "bl-12", "bl-13", "bl-9", "hayo-12", "hayo-13", "hayo-14", "hayo-15", "hayo-16",
        "hotate-20", "hotate-21", "hotate-22", "hotate-23", "hotate-24", "p1", "p2", "p3"
    ]
    /// The pages as PNG files, which the research read; p2 (7 MP) is missing from the folder.
    static let pagesFolder = "research/mt-spike/ocr/pages"

    static func ms(_ duration: Duration) -> Double {
        Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15
    }

    static func report(_ line: String) {
        print("MT3 | \(line)")
    }
}

/// A box as the research's comparisons write it: corners, score, class.
struct ReferenceBox: Equatable, Sendable {
    var x0: Double, y0: Double, x1: Double, y1: Double
    var score: Double
    var label: Int

    init(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double, score: Double, label: Int) {
        (self.x0, self.y0, self.x1, self.y1, self.score, self.label) = (x0, y0, x1, y1, score, label)
    }

    /// From a list of at least six numbers.
    init?(_ values: [Any]) {
        let numbers = values.compactMap { ($0 as? NSNumber)?.doubleValue }
        guard numbers.count >= 6 else { return nil }
        self.init(numbers[0], numbers[1], numbers[2], numbers[3], score: numbers[4], label: Int(numbers[5].rounded()))
    }

    init(_ rect: CGRect, score: Float, label: Int, scaleX: Double = 1, scaleY: Double = 1) {
        self.init(rect.minX * scaleX, rect.minY * scaleY, rect.maxX * scaleX, rect.maxY * scaleY, score: Double(score), label: label)
    }

    func overlap(_ other: ReferenceBox) -> Double {
        let width = max(0, min(x1, other.x1) - max(x0, other.x0)), height = max(0, min(y1, other.y1) - max(y0, other.y0))
        let shared = width * height
        let union = (x1 - x0) * (y1 - y0) + (other.x1 - other.x0) * (other.y1 - other.y0) - shared
        return union > 0 ? shared / union : 0
    }
}

/// The research's `detmatch.py`: boxes at or above the threshold on each side are matched
/// greedily, reference by reference, to the unused box of the same class with the largest
/// overlap, matched at 0.5 and counted at 0.9. An unmatched box whose twin (overlap 0.9 or more,
/// same class) exists on the other side below the threshold only crossed the threshold.
struct BoxMatch: CustomStringConvertible {
    var reference = 0, found = 0, matched = 0, matchedLoosely = 0
    var vanished = 0, appeared = 0, crossedDown = 0, crossedUp = 0

    init() {}

    init(reference all: [ReferenceBox], found allFound: [ReferenceBox], threshold: Double) {
        let references = all.filter { $0.score >= threshold }, found = allFound.filter { $0.score >= threshold }
        reference = references.count
        self.found = found.count
        var used = Set<Int>()
        var unmatchedReferences: [ReferenceBox] = []
        for box in references {
            var best = 0.0, bestIndex = -1
            for (index, candidate) in found.enumerated() where !used.contains(index) && candidate.label == box.label {
                let overlap = box.overlap(candidate)
                if overlap > best { (best, bestIndex) = (overlap, index) }
            }
            if bestIndex >= 0, best >= 0.5 {
                used.insert(bestIndex)
                matchedLoosely += 1
                if best >= 0.9 { matched += 1 }
            } else {
                unmatchedReferences.append(box)
            }
        }
        func twin(_ box: ReferenceBox, in pool: [ReferenceBox]) -> Bool {
            pool.contains { $0.label == box.label && $0.score < threshold && box.overlap($0) >= 0.9 }
        }
        let unmatchedFound = found.enumerated().filter { !used.contains($0.offset) }.map(\.element)
        crossedDown = unmatchedReferences.filter { twin($0, in: allFound) }.count
        crossedUp = unmatchedFound.filter { twin($0, in: all) }.count
        vanished = unmatchedReferences.count - crossedDown
        appeared = unmatchedFound.count - crossedUp
    }

    static func + (lhs: BoxMatch, rhs: BoxMatch) -> BoxMatch {
        var sum = BoxMatch()
        sum.reference = lhs.reference + rhs.reference
        sum.found = lhs.found + rhs.found
        sum.matched = lhs.matched + rhs.matched
        sum.matchedLoosely = lhs.matchedLoosely + rhs.matchedLoosely
        sum.vanished = lhs.vanished + rhs.vanished
        sum.appeared = lhs.appeared + rhs.appeared
        sum.crossedDown = lhs.crossedDown + rhs.crossedDown
        sum.crossedUp = lhs.crossedUp + rhs.crossedUp
        return sum
    }

    var share: Double { reference == 0 ? 1 : Double(matched) / Double(reference) }

    var description: String {
        String(
            format: "%d/%d matched at 0.9 (%.1f%%), %d at 0.5; found %d; vanished %d, appeared %d, crossed down %d, up %d",
            matched, reference, share * 100, matchedLoosely, found, vanished, appeared, crossedDown, crossedUp
        )
    }
}

/// Reads one float32 array from a numpy `.npz` file (a zip archive, deflated, with zip64 sizes).
enum NPZ {
    struct Failure: Error {}

    static func floats(_ name: String, in url: URL) throws -> (shape: [Int], values: [Float]) {
        let data = try Data(contentsOf: url)
        var offset = 0
        func integer(_ at: Int, _ size: Int) -> Int {
            (0..<size).reduce(0) { $0 | Int(data[data.startIndex + at + $1]) << (8 * $1) }
        }
        while offset + 30 <= data.count, integer(offset, 4) == 0x0403_4B50 {
            let method = integer(offset + 8, 2)
            var compressed = integer(offset + 18, 4), uncompressed = integer(offset + 22, 4)
            let nameLength = integer(offset + 26, 2), extraLength = integer(offset + 28, 2)
            let entryName = String(decoding: data[(data.startIndex + offset + 30)..<(data.startIndex + offset + 30 + nameLength)], as: UTF8.self)
            var extra = offset + 30 + nameLength
            let extraEnd = extra + extraLength
            while extra + 4 <= extraEnd {
                let id = integer(extra, 2), size = integer(extra + 2, 2)
                if id == 1 {
                    var field = extra + 4
                    if uncompressed == 0xFFFF_FFFF { uncompressed = integer(field, 8); field += 8 }
                    if compressed == 0xFFFF_FFFF { compressed = integer(field, 8) }
                }
                extra += 4 + size
            }
            let start = extraEnd
            if entryName == name {
                let bytes = data[(data.startIndex + start)..<(data.startIndex + start + compressed)]
                let npy = method == 0 ? Data(bytes) : try inflate(Data(bytes), size: uncompressed)
                return try parse(npy)
            }
            offset = start + compressed
        }
        throw Failure()
    }

    private static func inflate(_ data: Data, size: Int) throws -> Data {
        var output = Data(count: size)
        let written = output.withUnsafeMutableBytes { out in
            data.withUnsafeBytes { input in
                compression_decode_buffer(
                    out.bindMemory(to: UInt8.self).baseAddress!, size, input.bindMemory(to: UInt8.self).baseAddress!,
                    data.count, nil, COMPRESSION_ZLIB
                )
            }
        }
        guard written == size else { throw Failure() }
        return output
    }

    private static func parse(_ npy: Data) throws -> (shape: [Int], values: [Float]) {
        guard npy.count > 10 else { throw Failure() }
        let headerLength = Int(npy[npy.startIndex + 8]) | Int(npy[npy.startIndex + 9]) << 8
        let header = String(decoding: npy[(npy.startIndex + 10)..<(npy.startIndex + 10 + headerLength)], as: UTF8.self)
        guard header.contains("'<f4'"), let open = header.range(of: "'shape': ("),
              let close = header[open.upperBound...].firstIndex(of: ")")
        else { throw Failure() }
        let shape = header[open.upperBound..<close].split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        let body = npy[(npy.startIndex + 10 + headerLength)...]
        let values = body.withUnsafeBytes { raw in (0..<(raw.count / 4)).map { raw.loadUnaligned(fromByteOffset: $0 * 4, as: Float.self) } }
        return (shape, values)
    }
}
