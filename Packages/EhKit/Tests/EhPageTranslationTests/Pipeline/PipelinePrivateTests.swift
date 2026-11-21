import CoreGraphics
import CoreML
@testable import EhPageTranslation
import EhModels
import Foundation
import Testing

/// The opt-in tier for the pipeline: the real detectors and readers on the test pages that
/// are on disk, scored as the research scored its end-to-end run, on this Mac's CPU.
///
/// What it settles: the lines read exactly against the research's; whether the rule that
/// reads a "sound effect" box in a balloon as dialogue gains lines and loses none; the two
/// pairs with ogkalu v4-s; what the 4-megapixel cap costs the page it reduces; and that the
/// real stages join into one pipeline whose page is drawn the same from its stored text.
///
/// Nothing of a page is printed: counts and the truth's item ids only.
@Suite(.privateFolder, .serialized) struct PipelinePrivateTests {
    typealias Scoring = PipelineScoring

    static func report(_ line: String) {
        print("MT8 | \(line)")
    }

    // MARK: Models

    static func detector(_ choice: TextDetectorChoice) async throws -> any TextDetector {
        let root = "models/det-phone"
        switch choice {
        case .k2xl:
            return try await TextDetectors.load(
                .k2xl, compiledModel: ReferenceSupport.compiledModel("\(root)/k2xl/K2XL-r768-fp16.mlpackage"), computeUnits: .cpuOnly
            )
        case .v4s:
            // The shipped half-precision file scores every query as text on this Intel Mac's
            // CPU and is right on its GPU (the phone's CPU is right, by the research).
            return try await TextDetectors.load(
                .v4s, compiledModel: ReferenceSupport.compiledModel("\(root)/v4s/V4S-fp16.mlpackage"), computeUnits: .cpuAndGPU
            )
        case .yolo26s:
            return try await TextDetectors.load(
                .yolo26s, compiledModel: ReferenceSupport.compiledModel("\(root)/yolo26/YOLO26-fp16.mlpackage"), computeUnits: .cpuOnly
            )
        case .rtmdet2:
            return try await TextDetectors.load(
                .rtmdet2, compiledModel: ReferenceSupport.compiledModel("\(root)/rtmdet/RTMDet2-fp16.mlpackage"), computeUnits: .cpuOnly
            )
        }
    }

    static func reader(_ choice: TextReaderChoice) async throws -> any TextReader {
        switch choice {
        case .cpt2: return try await ReadersPrivateTests.cptReader("fp16")
        case .narSmall:
            return try await NARReader.load(
                compiledModel: ReferenceSupport.compiledModel("\(ReadersPrivateTests.nar)/coreml/mangaocr_nar_small_fp16.mlpackage"),
                vocabulary: PrivateFolder.required().url("\(ReadersPrivateTests.nar)/nar_vocabulary_6817.json"), computeUnits: .cpuOnly
            )
        }
    }

    /// The test pages whose picture is on disk (17 of the 18: the 7-megapixel page is missing).
    static func pages() throws -> [String] {
        try ResearchReferences.pageNames(in: PrivateFolder.required())
    }

    // MARK: Detecting and reading once

    /// The detector's blocks of every page on disk, each read by every reader.
    struct Readings: Sendable {
        /// By page, then by reader.
        var blocks: [String: [TextReaderChoice: [Scoring.ReadBlock]]] = [:]
        var bitmaps: [String: PageBitmap] = [:]
        var detectedBlocks = 0, soundEffects = 0, soundEffectsInBalloons = 0
    }

    /// The default detector's readings at full size, made once: two tests score them.
    actor DefaultReadings {
        static let shared = DefaultReadings()
        private var task: Task<Readings, any Error>?

        func readings() async throws -> Readings {
            if let task { return try await task.value }
            let task = Task { try await PipelinePrivateTests.readings(.k2xl, readers: [.cpt2, .narSmall]) }
            self.task = task
            return try await task.value
        }
    }

    /// - Parameter reducedTo: the share of its pixels each page is brought down to; `nil`
    ///   reads the pages as the app does.
    static func readings(
        _ detectorChoice: TextDetectorChoice, readers choices: [TextReaderChoice], reducedTo share: Double? = nil
    ) async throws -> Readings {
        let folder = try PrivateFolder.required()
        let detector = try await detector(detectorChoice)
        var readers: [TextReaderChoice: any TextReader] = [:]
        for choice in choices { readers[choice] = try await reader(choice) }
        var readings = Readings()
        for page in try pages() {
            let data = try Data(contentsOf: folder.url("\(ResearchReferences.pages)/\(page).png"))
            var bitmap = try PageBitmap(data: data)
            if let share {
                bitmap = try PageBitmap(data: data, maximumPixelCount: Int(Double(bitmap.width * bitmap.height) * share))
            }
            let detected = try await detector.detect(bitmap).blocks
            readings.bitmaps[page] = bitmap
            readings.detectedBlocks += detected.count
            readings.soundEffects += detected.filter { $0.kind == .soundEffect }.count
            readings.soundEffectsInBalloons += detected.filter { $0.kind == .soundEffect && $0.balloon != nil }.count
            for (choice, reader) in readers {
                var read: [Scoring.ReadBlock] = []
                for block in detected {
                    read.append(Scoring.ReadBlock(
                        box: block.box, isSoundEffect: block.kind == .soundEffect, isInBalloon: block.balloon != nil,
                        text: try await reader.read(block, on: bitmap)
                    ))
                }
                readings.blocks[page, default: [:]][choice] = read
            }
        }
        return readings
    }

    /// The lines read exactly over the pages on disk, with the lines there are.
    static func score(_ readings: Readings, reader: TextReaderChoice, rule: Scoring.Rule) throws -> Scoring.PageScore {
        let folder = try PrivateFolder.required()
        var total = Scoring.PageScore()
        for (page, byReader) in readings.blocks {
            guard let blocks = byReader[reader], let bitmap = readings.bitmaps[page] else { continue }
            let truth = try Scoring.truth(of: page, in: folder)
            let score = Scoring.score(blocks, rule: rule, truth: truth, bitmap: bitmap)
            total.exact.formUnion(score.exact)
            total.found.formUnion(score.found)
            total.lines.formUnion(score.lines)
        }
        return total
    }

    static func summary(_ name: String, _ readings: Readings, reader: TextReaderChoice) throws -> [Scoring.Rule: Scoring.PageScore] {
        var scores: [Scoring.Rule: Scoring.PageScore] = [:]
        for rule in Scoring.Rule.allCases {
            let score = try score(readings, reader: reader, rule: rule)
            scores[rule] = score
            report("\(name), \(rule.rawValue): \(score.exact.count)/\(score.lines.count) lines exact, \(score.found.count) found")
        }
        return scores
    }

    // MARK: The default detector

    /// KoharuLayout 2XL with both readers: the lines read exactly beside the research's, and
    /// the balloon rule.
    @Test func theDefaultDetectorsLinesAndTheBalloonRule() async throws {
        let folder = try PrivateFolder.required()
        let readings = try await DefaultReadings.shared.readings()
        Self.report(
            "k2xl on \(readings.bitmaps.count) pages: \(readings.detectedBlocks) blocks, \(readings.soundEffects) labelled "
                + "sound effects, \(readings.soundEffectsInBalloons) of them with their centre in a balloon"
        )
        for (reader, pair, floor) in [(TextReaderChoice.cpt2, "koharu_2xl+mocr_cpt", Self.floors.k2xlCPT), (.narSmall, "koharu_2xl+nar_small", Self.floors.k2xlNAR)] {
            let scores = try Self.summary("k2xl+\(reader.rawValue)", readings, reader: reader)
            let every = try #require(scores[.everyBox]), text = try #require(scores[.textOnly])
            let rule = try #require(scores[.balloonRule])

            // The research read every box, sound effects too; on the pages that are on disk
            // its run gave this many of these lines.
            let research = try Scoring.researchExactLines(pair: pair, in: folder).intersection(every.lines)
            Self.report(
                "k2xl+\(reader.rawValue), research on the same \(every.lines.count) lines: \(research.count) exact; "
                    + "here \(every.exact.count): \(every.exact.intersection(research).count) the same lines, "
                    + "\(every.exact.subtracting(research).count) gained, \(research.subtracting(every.exact).count) lost"
            )
            #expect(every.lines.count == 130, "the 149 lines without the missing page's 19")
            // Not the research's count: its 115 of 149 (102 of these 130) read every box,
            // sound effects too, from PyTorch's boxes. The floors are what this code reads.
            #expect(every.exact.count >= floor.everyBox)
            #expect(text.exact.count >= floor.textOnly)
            #expect(rule.exact.count >= text.exact.count)

            // The rule is kept only if it gains lines and loses none.
            let gained = rule.exact.subtracting(text.exact), lost = text.exact.subtracting(rule.exact)
            Self.report("k2xl+\(reader.rawValue), balloon rule against text boxes only: \(gained.count) lines gained, \(lost.count) lost")
            #expect(PipelineRules.readsSoundEffectsInBalloonsByDefault == (!gained.isEmpty && lost.isEmpty))
        }
        // What the rule reads that is no dialogue: a box in a balloon that lies on a drawn
        // sound effect of the truth and on no line.
        var onSoundEffects = 0, onLines = 0, onNothing = 0
        for (page, byReader) in readings.blocks {
            let truth = try Scoring.truth(of: page, in: folder)
            for block in byReader[.cpt2] ?? [] where block.isSoundEffect && block.isInBalloon {
                let best = truth.items.max { $0.rect.intersection(block.box).area < $1.rect.intersection(block.box).area }
                guard let best, best.rect.intersection(block.box).area > 0 else {
                    onNothing += 1
                    continue
                }
                if best.type == "sfx" { onSoundEffects += 1 } else { onLines += 1 }
            }
        }
        Self.report(
            "k2xl, the \(readings.soundEffectsInBalloons) boxes the balloon rule adds: \(onLines) lie on dialogue or notes, "
                + "\(onSoundEffects) on drawn sound effects, \(onNothing) on nothing in the truth"
        )
    }

    // MARK: ogkalu v4-s

    /// The two pairs with the detector everyone can have, scored for the first time. It has
    /// no sound-effect class, so there is nothing for the balloon rule to add.
    @Test func ogkaluV4SWithBothReaders() async throws {
        let readings = try await Self.readings(.v4s, readers: [.cpt2, .narSmall])
        Self.report("v4s on \(readings.bitmaps.count) pages: \(readings.detectedBlocks) blocks, \(readings.soundEffects) labelled sound effects")
        #expect(readings.soundEffects == 0)
        for (reader, floor) in [(TextReaderChoice.cpt2, Self.floors.v4sCPT), (.narSmall, Self.floors.v4sNAR)] {
            let score = try Self.score(readings, reader: reader, rule: .textOnly)
            Self.report("v4s+\(reader.rawValue): \(score.exact.count)/\(score.lines.count) lines exact, \(score.found.count) found")
            #expect(score.lines.count == 130)
            #expect(score.exact.count >= floor)
        }
    }

    // MARK: The cap

    /// The one test page above the 4-megapixel cap is not on disk, but the crops of its
    /// lines are (the truth's boxes with 4 pixels around them). Each is read at full size and
    /// brought down by the factor the cap brings that page down by, with the decoder's own
    /// reduction: what the cap costs reading from perfect boxes.
    @Test func theCapOnTheLinesOfThePageItReduces() async throws {
        let folder = try PrivateFolder.required()
        let truth = try Scoring.truth(of: "p2", in: folder)
        let capped = PageBitmap.cappedSize(width: truth.size[0], height: truth.size[1], maximumPixelCount: PageBitmap.maximumPixelCount)
        let factor = Double(capped.width) / Double(truth.size[0])
        let reader = try await Self.reader(.cpt2)
        var full = 0, reduced = 0, same = 0, lines = 0, lost: [String] = [], gained: [String] = []
        for item in truth.items where item.isScoredLine {
            let name = item.id.replacingOccurrences(of: "#", with: "_")
            let data = try Data(contentsOf: folder.url("\(ReadersPrivateTests.crops)/\(name).png"))
            let crop = try PageBitmap(data: data)
            let small = try PageBitmap(data: data, maximumPixelCount: Int(Double(crop.width * crop.height) * factor * factor))
            let atFullSize = try await reader.read(crop.cgImage), atTheCap = try await reader.read(small.cgImage)
            let expected = TextNormalisation.normalise(item.text)
            let isExactFull = TextNormalisation.normalise(atFullSize) == expected
            let isExactReduced = TextNormalisation.normalise(atTheCap) == expected
            lines += 1
            if isExactFull { full += 1 }
            if isExactReduced { reduced += 1 }
            if atFullSize == atTheCap { same += 1 }
            if isExactFull, !isExactReduced { lost.append(item.id) }
            if !isExactFull, isExactReduced { gained.append(item.id) }
        }
        Self.report(String(
            format: "the cap on p2's lines (%d × %d becomes %d × %d, a factor of %.3f): %d lines; %d exact at full size, "
                + "%d at the cap's size; %d read the same; lost %@, gained %@",
            truth.size[0], truth.size[1], capped.width, capped.height, factor, lines, full, reduced, same,
            "\(lost)", "\(gained)"
        ))
        #expect(lines == 19)
        #expect(lost.isEmpty, "the cap loses nothing on the page it reduces, from perfect boxes")
    }

    /// A harsher case than the cap ever makes: every page on disk reduced by the factor the
    /// cap reduces the 7-megapixel page by, although their lettering is smaller to begin with.
    /// Reported, not required: these pages are never reduced in the app.
    @Test func thePagesOnDiskReducedLikeThePageOverTheCap() async throws {
        let factor = 4_000_000.0 / (2297.0 * 3123.0)
        let full = try await DefaultReadings.shared.readings()
        let reduced = try await Self.readings(.k2xl, readers: [.cpt2], reducedTo: factor)
        let atFullSize = try Self.score(full, reader: .cpt2, rule: .everyBox)
        // The truth is in full-size pixels: the reduced page's boxes are scaled back up.
        var scaled = reduced
        for (page, byReader) in reduced.blocks {
            guard let small = reduced.bitmaps[page], let large = full.bitmaps[page] else { continue }
            let sx = CGFloat(large.width) / CGFloat(small.width), sy = CGFloat(large.height) / CGFloat(small.height)
            scaled.blocks[page] = byReader.mapValues { blocks in
                blocks.map { block in
                    var block = block
                    block.box = CGRect(x: block.box.minX * sx, y: block.box.minY * sy, width: block.box.width * sx, height: block.box.height * sy)
                    return block
                }
            }
            scaled.bitmaps[page] = large
        }
        let atTheFactor = try Self.score(scaled, reader: .cpt2, rule: .everyBox)
        Self.report(String(
            format: "k2xl+cpt2, every box, pages reduced to %.0f%% of their pixels: %d/%d lines exact against %d at full size "
                + "(%d lost, %d gained)",
            factor * 100, atTheFactor.exact.count, atTheFactor.lines.count, atFullSize.exact.count,
            atFullSize.exact.subtracting(atTheFactor.exact).count, atTheFactor.exact.subtracting(atFullSize.exact).count
        ))
        #expect(atTheFactor.lines.count == atFullSize.lines.count)
    }

    // MARK: The stages joined

    /// The real detector, reader and translator as one pipeline on two pages, loaded as the
    /// app loads them, then drawn, written and read back: the first time the halves meet.
    @Test func theRealStagesJoinIntoOnePipelineAndAPageIsDrawnTheSameFromItsStoredText() async throws {
        let folder = try PrivateFolder.required()
        let configuration = PipelineConfiguration(
            modelSet: .default,
            detector: try await ReferenceSupport.compiledModel("models/det-phone/k2xl/K2XL-r768-fp16.mlpackage"),
            reader: .cpt2(
                encoder: try await ReferenceSupport.compiledModel("\(ReadersPrivateTests.cpt)/CPTEncoder-fp16.mlpackage"),
                decoder: try await ReferenceSupport.compiledModel("\(ReadersPrivateTests.cpt)/CPTDecoder-fp16.mlpackage"),
                vocabulary: try folder.url("\(ReadersPrivateTests.cpt)/vocab.txt")
            ),
            translator: try await Self.installedTranslator(folder),
            detectorUnits: .cpuOnly, readerUnits: .cpuOnly, translatorUnits: .cpuOnly
        )
        let clock = ContinuousClock()
        let loadStart = clock.now
        let pipeline = try await PagePipeline.load(configuration)
        Self.report(String(
            format: "pipeline loaded in %.1f s (detector %.1f, reader %.1f, translator %.1f)",
            ReferenceSupport.ms(clock.now - loadStart) / 1000, ReferenceSupport.ms(pipeline.loadTimings.detector) / 1000,
            ReferenceSupport.ms(pipeline.loadTimings.reader) / 1000, ReferenceSupport.ms(pipeline.loadTimings.translator) / 1000
        ))
        let reader = try await Self.reader(.cpt2)
        let output = FileManager.default.temporaryDirectory.appending(path: "EhPageTranslationTests-pipeline", directoryHint: .isDirectory)
        for page in ["p3", "hotate-20"] {
            let bitmap = try ResearchReferences.bitmap(of: page, in: folder)
            let text = try await pipeline.text(of: bitmap)
            let translated = text.blocks.filter { !$0.translation.isEmpty }
            // Every block the pipeline kept as text has its reading and its translation, and
            // the reading is the reader's own.
            #expect(!translated.isEmpty)
            for block in text.blocks where block.kind != .soundEffect {
                #expect(!block.source.isEmpty && !block.translation.isEmpty)
                #expect(try await reader.read(block, on: bitmap) == block.source)
            }
            #expect(text.blocks.filter { $0.kind == .soundEffect }.allSatisfy { $0.source.isEmpty && $0.translation.isEmpty })

            let made = text.translation(gid: "1", pageIndex: 1, modelSetKey: PageTranslationModelSet.default.key, createdAt: .now)
            var stored = made
            stored.regions = try JSONDecoder().decode([TranslatedRegion].self, from: JSONEncoder().encode(made.regions))
            let first = try await PageDrawer.draw(made, on: bitmap)
            let again = try await PageDrawer.draw(stored, on: bitmap)
            #expect(first.patches == again.patches, "a page drawn again from its stored text is the same picture")
            #expect(!first.patches.isEmpty)

            let url = output.appending(path: "\(page).patch")
            let bytes = try await PatchFile.write(
                first.patches, imageWidth: bitmap.width, imageHeight: bitmap.height, colorSpace: bitmap.colorSpace, to: url
            )
            let file = try await PatchFile.read(from: url)
            #expect(file.placements.count == first.patches.count)
            try? FileManager.default.removeItem(at: url)
            Self.report(String(
                format: "%@ through the pipeline: %d blocks found, %d read, %d translated, %d sound effects kept; "
                    + "detect %.0f ms, read %.0f ms, translate %.0f ms; drawn %d patches in %.0f ms (unoptimised build), file %d bytes",
                page, text.timings.blocksFound, text.timings.blocksRead, translated.count,
                text.blocks.filter { $0.kind == .soundEffect }.count,
                ReferenceSupport.ms(text.timings.detection.network), ReferenceSupport.ms(text.timings.reading),
                ReferenceSupport.ms(text.timings.translating), first.patches.count, ReferenceSupport.ms(first.timings.total), bytes
            ))
        }
    }

    /// The translator's release as the model store installs it: the author's layout with each
    /// package compiled in its place. Made of links, so nothing is copied.
    static func installedTranslator(_ folder: PrivateFolder) async throws -> URL {
        let release = try folder.url("models/jmt/dl")
        let root = FileManager.default.temporaryDirectory.appending(path: "EhPageTranslationTests-jmt-installed", directoryHint: .isDirectory)
        try? FileManager.default.removeItem(at: root)
        try FileManager.default.createDirectory(at: root.appending(path: "coreml"), withIntermediateDirectories: true)
        for name in ["config.json", "joint.model", "tokenizer", "coreml/host"] {
            try FileManager.default.createSymbolicLink(at: root.appending(path: name), withDestinationURL: release.appending(path: name))
        }
        for name in ["encoder_static_fp16", "decoder_fp16"] {
            let compiled = try await ReferenceSupport.compiledModel("models/jmt/dl/coreml/\(name).mlpackage")
            try FileManager.default.createSymbolicLink(at: root.appending(path: "coreml/\(name).mlmodelc"), withDestinationURL: compiled)
        }
        return root
    }

    // MARK: What was measured

    /// The lines read exactly on the 17 pages on disk (130 of the 149 lines), measured on
    /// this Mac on 2026-11-20. The tests fail when a change reads fewer.
    ///
    /// - KoharuLayout 2XL with CPT v2: 98 with every box read, where the research's run
    ///   (PyTorch, every box) read 102 of the same lines; 79 with text boxes only and 83 with
    ///   the balloon rule, which is what the app does. With nar-small: 91, 73 and 78.
    /// - ogkalu v4-s: 93 with CPT v2 and 86 with nar-small. Its floors leave three lines of
    ///   room: it runs on this Mac's GPU here, whose half-precision results differ a little
    ///   from one loading to the next.
    static let floors = (
        k2xlCPT: (everyBox: 98, textOnly: 79), k2xlNAR: (everyBox: 91, textOnly: 73), v4sCPT: 90, v4sNAR: 83
    )
}

private extension CGRect {
    var area: CGFloat { isNull ? 0 : width * height }
}
