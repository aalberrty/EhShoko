import CoreGraphics
@testable import EhPageTranslation
import EhModels
import Foundation
import Synchronization

/// What the stub stages did, in the order they did it.
final class StageLog: Sendable {
    private let entries = Mutex<[String]>([])

    func add(_ entry: String) {
        entries.withLock { $0.append(entry) }
    }

    var all: [String] { entries.withLock { $0 } }
}

/// Counts calls from any thread.
final class CallCounter: Sendable {
    private let value = Mutex(0)

    /// The number of this call, from 1.
    func next() -> Int {
        value.withLock { value in
            value += 1
            return value
        }
    }

    var count: Int { value.withLock { $0 } }
}

/// A detector that gives the blocks it was told to, for each region it is asked about.
struct StubDetector: TextDetector {
    var choice: TextDetectorChoice = .k2xl
    var log: StageLog?
    var blocks: @Sendable (PixelRect) -> [TextBlock]
    var onDetect: (@Sendable () async throws -> Void)?

    func detect(_ page: PageBitmap, in region: PixelRect) async throws -> DetectedText {
        log?.add("detect \(region.y0)")
        try await onDetect?()
        return DetectedText(blocks: blocks(region))
    }
}

/// A reader that tells blocks apart by the size of the crop it is handed, which is the
/// block's box with 4 pixels around it.
struct StubReader: TextReader {
    var choice: TextReaderChoice = .cpt2
    var log: StageLog?
    /// The text of a crop by its size, "width x height"; a size that is not listed reads as
    /// nothing.
    var texts: [String: String]
    /// Called after each reading with how many crops were read so far.
    var onRead: (@Sendable (Int) async throws -> Void)?
    private let count = CallCounter()

    init(
        log: StageLog? = nil, texts: [String: String], onRead: (@Sendable (Int) async throws -> Void)? = nil
    ) {
        self.log = log
        self.texts = texts
        self.onRead = onRead
    }

    func read(_ crop: CGImage) async throws -> String {
        let size = "\(crop.width)x\(crop.height)"
        log?.add("read \(size)")
        try await onRead?(count.next())
        return texts[size] ?? ""
    }

    /// The crop size of a block whose box is `width` × `height` and lies clear of the page's
    /// edges.
    static func size(_ width: Int, _ height: Int) -> String {
        "\(width + 8)x\(height + 8)"
    }
}

/// A translator that looks each line up; a line that is not listed gets `nil`.
struct StubTranslator: PageTranslator {
    var log: StageLog?
    var translations: [String: String]
    /// Returned instead of one result a line, to stand for a translator that misbehaves.
    var fixedAnswer: [String?]?

    func translate(_ lines: [String]) async throws -> [String?] {
        log?.add("translate \(lines.joined(separator: "|"))")
        try Task.checkCancellation()
        return fixedAnswer ?? lines.map { translations[$0] }
    }
}

extension PageBitmap {
    /// A page of white paper.
    static func blank(width: Int, height: Int) throws -> PageBitmap {
        try PageBitmap(
            width: width, height: height, originalWidth: width, originalHeight: height,
            pixels: Data(repeating: 255, count: width * height * 4), colorSpace: SyntheticImages.sRGB
        )
    }
}

extension TextBlock {
    /// A block of the given kind and box; its balloon, if any, is a box a little larger.
    static func stub(
        _ kind: RegionKind, x: Int, y: Int, width: Int, height: Int, inBalloon: Bool = false, score: Float = 0.9
    ) -> TextBlock {
        let box = CGRect(x: x, y: y, width: width, height: height)
        return TextBlock(
            box: box, kind: kind, isVertical: height > width, score: score,
            balloon: inBalloon ? Balloon(box: box.insetBy(dx: -10, dy: -10)) : nil
        )
    }
}
