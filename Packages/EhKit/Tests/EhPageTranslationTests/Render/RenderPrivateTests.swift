import CoreGraphics
import CoreML
@testable import EhPageTranslation
import EhModels
import Foundation
import Testing

/// The opt-in tier for drawing: the research's real pages, reference boxes and repaint model.
/// Nothing here prints or stores a page's text, and the pictures it makes go to the private
/// reports folder only.
@Suite(.privateFolder, .serialized) struct RenderPrivateTests {
    /// Where this task's private results go: beside the translation folder, never inside
    /// the repository.
    static func reports(_ folder: PrivateFolder) throws -> URL {
        let url = folder.root.deletingLastPathComponent().appending(path: "reports/MT5")
        try FileManager.default.createDirectory(at: url.appending(path: "pages"), withIntermediateDirectories: true)
        return url
    }

    struct Coverage: Codable {
        var items = 0
        /// The sum over the items of the share of each one's ink under the erase masks.
        var covered = 0.0
        /// The same for the reference boxes themselves: what any mask inside them can reach.
        var inBoxes = 0.0

        var share: Double { items > 0 ? covered / Double(items) : 0 }
        var ceiling: Double { items > 0 ? inBoxes / Double(items) : 0 }
    }

    /// The share of the truth's ink that the erase masks cover, for balloon text and for
    /// notes, with the masks made from the page's pixels inside the detector's reference
    /// boxes. Each block has the text of the truth item it lies on, as it would have the
    /// reader's.
    ///
    /// With `countingSoundEffects` the boxes the detector labelled sound effects are analysed
    /// too. That is how the research measured the detector's own masks, which cover 78% of
    /// the balloon ink on the Neural Engine and 91% where they are exact: the detector calls
    /// about a fifth of the dialogue it finds a sound effect, and its masks for those boxes
    /// counted.
    private func coverage(withMasks: Bool, countingSoundEffects: Bool) throws -> [String: Coverage] {
        let folder = try PrivateFolder.required()
        var result: [String: Coverage] = ["bubble": Coverage(), "free": Coverage()]
        for name in try ResearchReferences.pageNames(in: folder) {
            let bitmap = try ResearchReferences.bitmap(of: name, in: folder)
            let truth = try ResearchReferences.truth(of: name, in: folder)
            var blocks = try ResearchReferences.blocks(
                of: name, bitmap: bitmap, in: folder, withMasks: withMasks, includingSoundEffects: countingSoundEffects
            )
            ResearchReferences.assignText(to: &blocks, truth: truth)
            let analyzer = BlockAnalyzer()
            let erased = blocks.enumerated().compactMap { analyzer.analyze(page: bitmap, block: $1, index: $0)?.erase }
            let boxes = blocks.map { PixelRect(covering: $0.box) }
            for item in truth.items where result[item.type] != nil {
                guard let ink = TruthInk.mask(of: item.rect, bitmap: bitmap), ink.count > 0 else { continue }
                var covered = 0, boxed = 0
                for y in ink.rect.y0..<ink.rect.y1 {
                    for x in ink.rect.x0..<ink.rect.x1 where ink.contains(x, y) {
                        if erased.contains(where: { $0.contains(x, y) }) { covered += 1 }
                        if boxes.contains(where: { $0.contains(x, y) }) { boxed += 1 }
                    }
                }
                result[item.type]?.items += 1
                result[item.type]?.covered += Double(covered) / Double(ink.count)
                result[item.type]?.inBoxes += Double(boxed) / Double(ink.count)
            }
        }
        return result
    }

    @Test func thePixelMasksCoverTheBalloonInkOfTheTestPages() throws {
        let folder = try PrivateFolder.required()
        let withMasks = try coverage(withMasks: true, countingSoundEffects: true)
        let boxesOnly = try coverage(withMasks: false, countingSoundEffects: true)
        let report = [
            "allBoxes.withBalloonMasks": withMasks, "allBoxes.withBalloonBoxesOnly": boxesOnly,
            "textBoxesOnly.withBalloonMasks": try coverage(withMasks: true, countingSoundEffects: false)
        ]
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(report).write(to: Self.reports(folder).appending(path: "coverage.json"))
        // One of the research's 18 pages is not in the folder; the others hold 77 of its 93
        // balloon texts.
        let balloons = try #require(withMasks["bubble"]), stored = try #require(boxesOnly["bubble"])
        #expect(balloons.items >= 77)
        #expect(balloons.share >= 0.90, "balloon ink covered \(balloons.share), in the boxes \(balloons.ceiling)")
        // A page drawn again from its stored text has the balloons' boxes and no masks.
        #expect(stored.share >= 0.90, "without masks \(stored.share)")
    }

    // MARK: The repaint model

    static let repaintModel = "models/render/coreml/LaMa-fp16.mlpackage"
    static let tiles = "models/det-phone/lama/tiles"
    static let reference = "models/det-phone/lama/mac"

    /// The repaint model, compiled once into the temporary folder.
    static func inpainter(_ folder: PrivateFolder) async throws -> LamaInpainter {
        let compiled = FileManager.default.temporaryDirectory.appending(path: "EhPageTranslationTests-LaMa-fp16.mlmodelc")
        if !FileManager.default.fileExists(atPath: compiled.path) {
            let made = try await MLModel.compileModel(at: folder.url(repaintModel))
            try? FileManager.default.removeItem(at: compiled)
            try FileManager.default.moveItem(at: made, to: compiled)
        }
        return try LamaInpainter(compiledModel: compiled)
    }

    struct TileResult: Codable {
        var tile: Int
        var seconds: Double
        /// Against the Mac's reference of the same model file on the CPU.
        var largestDifference: Int
        var psnr: Double
        var psnrInMask: Double
    }

    @Test func theRepaintModelGivesTheResearchsTiles() async throws {
        let folder = try PrivateFolder.required()
        let inpainter = try await Self.inpainter(folder)
        var results: [TileResult] = []
        let clock = ContinuousClock()
        for number in 0..<10 {
            let tile = try PageBitmap(data: Data(contentsOf: folder.url("\(Self.tiles)/tile-\(number).png")))
            let hole = try PageBitmap(data: Data(contentsOf: folder.url("\(Self.tiles)/mask-\(number).png")))
            let expected = try PageBitmap(data: Data(contentsOf: folder.url("\(Self.reference)/LaMa-fp16-\(number).png")))
            try #require(tile.width == 512 && tile.height == 512 && hole.width == 512 && expected.width == 512)
            let mask = (0..<(512 * 512)).map { hole.pixels[$0 * 4] > 127 ? UInt8(1) : 0 }
            let start = clock.now
            let output = try await inpainter.repaint(tile: [UInt8](tile.pixels), mask: mask)
            let elapsed = clock.now - start
            var largest = 0, squares = 0.0, squaresInMask = 0.0, masked = 0
            for index in 0..<(512 * 512) {
                for channel in 0..<3 {
                    let difference = Int(output[index * 4 + channel]) - Int(expected.pixels[index * 4 + channel])
                    largest = max(largest, abs(difference))
                    squares += Double(difference * difference)
                    if mask[index] != 0 { squaresInMask += Double(difference * difference) }
                }
                if mask[index] != 0 { masked += 1 }
            }
            func psnr(_ sum: Double, _ count: Int) -> Double {
                10 * log10(255 * 255 / max(sum / Double(max(1, count) * 3), 1e-6))
            }
            results.append(TileResult(
                tile: number, seconds: Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18,
                largestDifference: largest, psnr: psnr(squares, 512 * 512), psnrInMask: psnr(squaresInMask, masked)
            ))
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(results).write(to: Self.reports(folder).appending(path: "lama-tiles.json"))
        // The reference ran the same file on the CPU; this runs it on the GPU, as the app does.
        for result in results {
            #expect(result.psnrInMask >= Self.minimumPSNR, "tile \(result.tile): \(result.psnrInMask) dB in the mask")
            #expect(result.psnr >= Self.minimumPSNR, "tile \(result.tile): \(result.psnr) dB")
        }
    }

    /// Measured on the development Mac: see the task's report.
    static let minimumPSNR = 40.0

    // MARK: Pictures for the owner

    /// Text that stands in where the research has no translation of a block: it shows the
    /// lettering, not a translation.
    static let filler = Array("这里是一段用来占位的译文只为了看排版的效果")

    @Test func aTranslatedPictureOfEachTestPage() async throws {
        let folder = try PrivateFolder.required()
        let reports = try Self.reports(folder)
        let inpainter = try await Self.inpainter(folder)
        struct PageSummary: Codable {
            var page: String
            var blocks: Int
            var drawn: Int
            var inBalloons: Int
            var repainted: Int
            var overflowing: Int
            var standIns: Int
            var milliseconds: [String: Double]
        }
        var summaries: [PageSummary] = []
        for name in try ResearchReferences.pageNames(in: folder) {
            let bitmap = try ResearchReferences.bitmap(of: name, in: folder)
            let truth = try ResearchReferences.truth(of: name, in: folder)
            let known = try ResearchReferences.translations(of: name, in: folder)
            var blocks = try ResearchReferences.blocks(of: name, bitmap: bitmap, in: folder, withMasks: true)
            let standIns = ResearchReferences.assignText(to: &blocks, truth: truth, translations: known, filler: Self.filler)
            let translated = blocks.filter { !$0.translation.isEmpty }.count
            let render = try await PageRenderer().render(page: bitmap, blocks: blocks, inpainter: inpainter)
            let image = try #require(render.composited(over: bitmap))
            try #require(PatchBuilder.pngData(of: image)).write(to: reports.appending(path: "pages/\(name).png"))
            func ms(_ duration: Duration) -> Double {
                Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15
            }
            summaries.append(PageSummary(
                page: name, blocks: blocks.count, drawn: render.blocks.count,
                inBalloons: render.blocks.filter(\.isInBalloon).count, repainted: render.blocks.filter(\.isRepainted).count,
                overflowing: render.blocks.filter(\.overflows).count, standIns: standIns,
                milliseconds: [
                    "analysis": ms(render.timings.analysis), "filling": ms(render.timings.filling),
                    "repainting": ms(render.timings.repainting), "fitting": ms(render.timings.fitting),
                    "drawing": ms(render.timings.drawing)
                ]
            ))
            #expect(render.failedRepaints == 0)
            #expect(render.blocks.count == translated, "\(name): \(render.blocks.count) of \(translated) drawn")
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(summaries).write(to: reports.appending(path: "pages.json"))
        #expect(summaries.count >= 17)
    }
}
