import CoreGraphics
import CoreML
@testable import EhPageTranslation
import EhModels
import Foundation
import ImageIO
import Testing

// The switch for drawn sound effects in the opt-in tier: every pair's figures in both of its
// states, and what drawing does to sound effects drawn on the artwork when it is on.
extension PipelinePrivateTests {
    // MARK: Every pair, with the switch off and on

    /// Every detector and reader pair as the app reads them: the boxes `PipelineRules` of the
    /// model set reads, with the switch for sound effects off and on. These are the figures of
    /// the selection screens (`PageTranslationMeasurements`), which must be what this scores.
    ///
    /// ogkalu v4-s has no sound-effect class, so the switch changes nothing with it. It runs on
    /// this Mac's GPU, whose half-precision results can differ a little from one loading to the
    /// next (MT5), so its figures may be off by up to three lines; the other three detectors run
    /// on the CPU and must give their figures exactly.
    @Test func everyPairWithTheSwitchOffAndOn() async throws {
        for detector in [TextDetectorChoice.k2xl, .yolo26s, .rtmdet2, .v4s] {
            let readings = detector == .k2xl
                ? try await DefaultReadings.shared.readings()
                : try await Self.readings(detector, readers: TextReaderChoice.allCases)
            Self.report(
                "\(detector.rawValue) on \(readings.bitmaps.count) pages: \(readings.detectedBlocks) blocks, "
                    + "\(readings.soundEffects) labelled sound effects, \(readings.soundEffectsInBalloons) in a balloon"
            )
            if !detector.labelsSoundEffects { #expect(readings.soundEffects == 0) }
            for reader in TextReaderChoice.allCases {
                for isOn in [false, true] {
                    let set = PageTranslationModelSet(detector: detector, reader: reader, translatesSoundEffects: isOn)
                    let score = try Self.score(readings, reader: reader, rules: PipelineRules(set))
                    let figure = PageTranslationMeasurements.linesReadExactly(
                        detector: detector, reader: reader, withSoundEffects: isOn
                    )
                    Self.report(
                        "\(detector.rawValue)+\(reader.rawValue), sound effects \(isOn ? "on" : "off"): "
                            + "\(score.exact.count)/\(score.lines.count) lines exact, \(score.found.count) found; "
                            + "the table says \(figure.value)"
                    )
                    #expect(score.lines.count == 130, "the 149 lines without the missing page's 19")
                    guard case let .tally(count, of: total) = figure.value else {
                        Issue.record("\(detector.rawValue)+\(reader.rawValue) has no figure")
                        continue
                    }
                    #expect(total == score.lines.count)
                    let room = detector == .v4s ? 3 : 0
                    #expect(abs(count - score.exact.count) <= room, "\(detector.rawValue)+\(reader.rawValue), on: \(isOn)")
                }
            }
        }
    }

    // MARK: Drawn sound effects with the switch on

    /// The default models with the switch for sound effects on, loaded as the app loads
    /// them, on every page on disk, drawn with the default repaint model: what happens to
    /// sound effects drawn on the artwork. Counts only; with `PAGE_TRANSLATION_LOOK` naming a
    /// folder, each page is also written there drawn both ways (`<page>-on.png`,
    /// `<page>-off.png`) for a person to look at. Those pictures are the test pages': they stay
    /// on this Mac, in a folder deleted after looking.
    @Test func drawnSoundEffectsWithTheSwitchOn() async throws {
        let folder = try PrivateFolder.required()
        let on = PageTranslationModelSet(translatesSoundEffects: true)
        let pipeline = try await PagePipeline.load(try await Self.defaultConfiguration(on, in: folder))
        // The setting reaches the pipeline with the model set.
        #expect(pipeline.rules == PipelineRules(on) && pipeline.rules.kindsRead.contains(.soundEffect))
        let inpainter = try await LamaInpainter(
            compiledModel: try await RenderPrivateTests.compiledRepaintModel(folder), computeUnits: .cpuAndGPU
        )
        let look = ProcessInfo.processInfo.environment["PAGE_TRANSLATION_LOOK"].map { URL(filePath: $0, directoryHint: .isDirectory) }
        var tally = SoundEffectTally()
        for page in try Self.pages() {
            let bitmap = try ResearchReferences.bitmap(of: page, in: folder)
            let text = try await pipeline.text(of: bitmap)
            let translation = text.translation(gid: "1", pageIndex: 1, modelSetKey: on.key, createdAt: .now)
            let blocks = PageDrawer.blocks(of: translation, on: bitmap)
            let render = try await PageRenderer().render(page: bitmap, blocks: blocks, inpainter: inpainter)
            tally.add(render, blocks: blocks, page: bitmap)
            tally.overlapping += text.timings.overlappingSoundEffects
            if let look {
                // The same page as the app draws it with the switch off: its sound effects unread.
                var off = translation
                off.regions = off.regions.map { $0.kind == .soundEffect ? TranslatedRegion(
                    box: $0.box, balloonBox: $0.balloonBox, kind: $0.kind, isVertical: $0.isVertical, score: $0.score
                ) : $0 }
                let plain = try await PageRenderer().render(page: bitmap, blocks: PageDrawer.blocks(of: off, on: bitmap), inpainter: inpainter)
                try Self.write(render.composited(over: bitmap), to: look.appending(path: "\(page)-on.png"))
                try Self.write(plain.composited(over: bitmap), to: look.appending(path: "\(page)-off.png"))
            }
        }
        Self.report(tally.summary)
        #expect(tally.drawn > 0, "with the switch on, drawn sound effects are erased and lettered")
    }

    static func write(_ image: CGImage?, to url: URL) throws {
        let image = try #require(image)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
    }

    /// What drawing did to the blocks that came out of the pipeline as sound effects.
    struct SoundEffectTally {
        var pages = 0, pagesWithOverflow = 0
        /// Sound effects that were read and translated, and of those, drawn; and those read but
        /// dropped for lying on another block.
        var translated = 0, drawn = 0, overlapping = 0
        /// Drawn on artwork, and in a balloon or box the page's pixels showed.
        var onArtwork = 0, inBalloon = 0, repainted = 0
        /// Lettering that did not fit its area at the smallest size.
        var overflowing = 0
        /// Patches much larger than the detector's box (more than three times its area).
        var farLargerPatches = 0
        /// Patches that reach the page's edge where the box does not.
        var atThePageEdge = 0
        var fontRatios: [Double] = []
        var patchRatios: [Double] = []

        mutating func add(_ render: PageRender, blocks: [TextBlock], page: PageBitmap) {
            pages += 1
            translated += blocks.filter { $0.kind == .soundEffect && !$0.translation.isEmpty }.count
            var overflowHere = false
            for block in render.blocks where blocks[block.index].kind == .soundEffect {
                drawn += 1
                if block.isInBalloon { inBalloon += 1 } else { onArtwork += 1 }
                if block.isRepainted { repainted += 1 }
                if block.overflows { overflowing += 1; overflowHere = true }
                let box = PixelRect(covering: blocks[block.index].box)
                let ratio = Double(block.patch.rect.area) / Double(max(1, box.area))
                patchRatios.append(ratio)
                if ratio > 3 { farLargerPatches += 1 }
                let rect = block.patch.rect
                let touches = rect.x0 <= 0 || rect.y0 <= 0 || rect.x1 >= page.width || rect.y1 >= page.height
                let boxTouches = box.x0 <= 1 || box.y0 <= 1 || box.x1 >= page.width - 1 || box.y1 >= page.height - 1
                if touches && !boxTouches { atThePageEdge += 1 }
                if block.measuredFontSize > 0 { fontRatios.append(block.fontSize / block.measuredFontSize) }
            }
            if overflowHere { pagesWithOverflow += 1 }
        }

        var summary: String {
            func median(_ values: [Double]) -> Double { values.isEmpty ? 0 : values.sorted()[values.count / 2] }
            return String(
                format: "sound effects with the switch on, %d pages: %d dropped for lying on another block, "
                    + "%d translated, %d drawn (%d on artwork, %d repainted, "
                    + "%d in a balloon or box); %d overflow their area, on %d pages; %d patches over three times their box "
                    + "(median %.2f); %d reach the page's edge where their box does not; lettering size against the "
                    + "original's, median %.2f",
                pages, overlapping, translated, drawn, onArtwork, repainted, inBalloon, overflowing, pagesWithOverflow,
                farLargerPatches, median(patchRatios), atThePageEdge, median(fontRatios)
            )
        }
    }
}
