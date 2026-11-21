import CoreGraphics
@testable import EhPageTranslation
import EhModels
import Foundation
import Synchronization
import Testing

@Suite struct PagePipelineTests {
    /// A balloon's line, a note, and a sound effect, from the right.
    static let dialogue = TextBlock.stub(.dialogue, x: 300, y: 40, width: 30, height: 100, inBalloon: true)
    static let note = TextBlock.stub(.aside, x: 200, y: 50, width: 20, height: 60)
    static let effect = TextBlock.stub(.soundEffect, x: 60, y: 60, width: 50, height: 70)
    static let texts = [StubReader.size(30, 100): "こんにちは", StubReader.size(20, 60): "えっ"]
    static let translations = ["こんにちは": "你好", "えっ": "诶"]

    static func pipeline(
        _ blocks: [TextBlock] = [dialogue, note, effect], texts: [String: String] = texts,
        translations: [String: String] = translations, log: StageLog? = nil, rules: PipelineRules = PipelineRules()
    ) -> PagePipeline {
        PagePipeline(
            detector: StubDetector(log: log, blocks: { _ in blocks }),
            reader: StubReader(log: log, texts: texts),
            translator: StubTranslator(log: log, translations: translations), rules: rules
        )
    }

    @Test func theStagesRunInOrderAndFillEachBlock() async throws {
        let log = StageLog()
        let stages = Mutex<[PipelineStage]>([])
        let page = try PageBitmap.blank(width: 400, height: 300)

        let text = try await Self.pipeline(log: log).text(of: page) { stage in stages.withLock { $0.append(stage) } }

        #expect(log.all == ["detect 0", "read 38x108", "read 28x68", "translate こんにちは|えっ"])
        #expect(stages.withLock { $0 } == [.found(blocks: 3), .read(blocks: 2), .translated(blocks: 2)])
        #expect(text.imageWidth == 400 && text.imageHeight == 300)
        #expect(text.blocks.map(\.source) == ["こんにちは", "えっ", ""])
        #expect(text.blocks.map(\.translation) == ["你好", "诶", ""])
        // The sound effect is kept with its box, unread, for a later layer.
        #expect(text.blocks.map(\.kind) == [.dialogue, .aside, .soundEffect])
        #expect(text.blocks[2].box == Self.effect.box)
        #expect(text.timings.tiles == 1 && text.timings.blocksFound == 3 && text.timings.blocksRead == 2)
    }

    @Test func aBlockThatReadsAsNothingIsDropped() async throws {
        let log = StageLog()
        var texts = Self.texts
        texts[StubReader.size(20, 60)] = " \n"
        let text = try await Self.pipeline(texts: texts, log: log).text(of: PageBitmap.blank(width: 400, height: 300))

        #expect(text.blocks.map(\.kind) == [.dialogue, .soundEffect])
        // The translator never sees it.
        #expect(log.all.last == "translate こんにちは")
        #expect(text.timings.emptyReadings == 1)
    }

    @Test func aLineTheTranslatorGivesNothingForLosesItsBlock() async throws {
        let text = try await Self.pipeline(translations: ["こんにちは": "你好"])
            .text(of: PageBitmap.blank(width: 400, height: 300))

        #expect(text.blocks.map(\.translation) == ["你好", ""])
        #expect(text.blocks.map(\.kind) == [.dialogue, .soundEffect])
        #expect(text.timings.untranslatedLines == 1)

        // A blank translation is nothing too.
        let blank = try await Self.pipeline(translations: ["こんにちは": "你好", "えっ": "  "])
            .text(of: PageBitmap.blank(width: 400, height: 300))
        #expect(blank.blocks.map(\.kind) == [.dialogue, .soundEffect])
    }

    @Test func aPageWithNothingToReadCallsNeitherReaderNorTranslator() async throws {
        let log = StageLog()
        let text = try await Self.pipeline([Self.effect], log: log).text(of: PageBitmap.blank(width: 400, height: 300))

        #expect(log.all == ["detect 0"])
        #expect(text.blocks == [Self.effect])
        #expect(!text.translation(gid: "1", pageIndex: 1, modelSetKey: "k", createdAt: .now).hasTranslatedText)
    }

    @Test func aSoundEffectInABalloonIsReadAsDialogueWhenTheRuleIsOn() async throws {
        let inBalloon = TextBlock.stub(.soundEffect, x: 100, y: 100, width: 24, height: 44, inBalloon: true)
        let texts = [StubReader.size(24, 44): "はぁ"], translations = ["はぁ": "哈啊"]
        let page = try PageBitmap.blank(width: 400, height: 300)

        var rules = PipelineRules()
        rules.readsSoundEffectsInBalloons = true
        let on = try await Self.pipeline([inBalloon, Self.effect], texts: texts, translations: translations, rules: rules)
            .text(of: page)
        // In reading order the effect outside a balloon stays what it was.
        #expect(on.blocks.map(\.kind) == [.dialogue, .soundEffect])
        #expect(on.blocks[0].translation == "哈啊")

        rules.readsSoundEffectsInBalloons = false
        let off = try await Self.pipeline([inBalloon, Self.effect], texts: texts, translations: translations, rules: rules)
            .text(of: page)
        #expect(off.blocks.map(\.kind) == [.soundEffect, .soundEffect])
        #expect(off.blocks.allSatisfy { $0.source.isEmpty && $0.translation.isEmpty })
    }

    @Test func onlyTheKindsOfTheRulesAreRead() async throws {
        let log = StageLog()
        let rules = PipelineRules(kindsRead: [.dialogue])
        let text = try await Self.pipeline(log: log, rules: rules).text(of: PageBitmap.blank(width: 400, height: 300))

        #expect(log.all == ["detect 0", "read 38x108", "translate こんにちは"])
        #expect(text.blocks.map(\.source) == ["こんにちは", "", ""])
    }

    @Test func aTranslatorMustAnswerEveryLine() async throws {
        let pipeline = PagePipeline(
            detector: StubDetector(blocks: { _ in [Self.dialogue, Self.note] }), reader: StubReader(texts: Self.texts),
            translator: StubTranslator(translations: [:], fixedAnswer: ["你好"])
        )
        await #expect(throws: PagePipelineError.lineCountMismatch(lines: 2, translations: 1)) {
            try await pipeline.text(of: PageBitmap.blank(width: 400, height: 300))
        }
    }

    // MARK: Cancellation

    /// Runs the pipeline in a task the stubs can cancel from inside, as the service cancels a
    /// page's task from outside.
    static func inATaskOfItsOwn(_ pipeline: PagePipeline) async throws -> PageText {
        let page = try PageBitmap.blank(width: 400, height: 300)
        return try await Task { try await pipeline.text(of: page) }.value
    }

    @Test func cancelledAfterTheDetectorNothingIsRead() async throws {
        let log = StageLog()
        let pipeline = PagePipeline(
            // A model call cannot be interrupted: the cancel is seen when it returns.
            detector: StubDetector(log: log, blocks: { _ in [Self.dialogue, Self.note] }, onDetect: {
                withUnsafeCurrentTask { $0?.cancel() }
            }),
            reader: StubReader(log: log, texts: Self.texts), translator: StubTranslator(log: log, translations: Self.translations)
        )
        await #expect(throws: CancellationError.self) { try await Self.inATaskOfItsOwn(pipeline) }
        #expect(log.all == ["detect 0"])
    }

    @Test func cancelledBetweenTwoBlocksTheSecondIsNotRead() async throws {
        let log = StageLog()
        let pipeline = PagePipeline(
            detector: StubDetector(log: log, blocks: { _ in [Self.dialogue, Self.note] }),
            reader: StubReader(log: log, texts: Self.texts, onRead: { number in
                if number == 1 { withUnsafeCurrentTask { $0?.cancel() } }
            }),
            translator: StubTranslator(log: log, translations: Self.translations)
        )
        await #expect(throws: CancellationError.self) { try await Self.inATaskOfItsOwn(pipeline) }
        #expect(log.all == ["detect 0", "read 38x108"])
    }

    @Test func cancelledAfterTheLastBlockNothingIsTranslated() async throws {
        let log = StageLog()
        let pipeline = PagePipeline(
            detector: StubDetector(log: log, blocks: { _ in [Self.dialogue, Self.note] }),
            reader: StubReader(log: log, texts: Self.texts, onRead: { number in
                if number == 2 { withUnsafeCurrentTask { $0?.cancel() } }
            }),
            translator: StubTranslator(log: log, translations: Self.translations)
        )
        await #expect(throws: CancellationError.self) { try await Self.inATaskOfItsOwn(pipeline) }
        #expect(!log.all.contains { $0.hasPrefix("translate") })
    }

    // MARK: Tall pages

    @Test func aTallPageIsDetectedTileByTile() async throws {
        let log = StageLog()
        // One block near the top, found in the first tile only; one in the rows two tiles share.
        let top = TextBlock.stub(.aside, x: 100, y: 40, width: 20, height: 60)
        let shared = TextBlock.stub(.aside, x: 100, y: 410, width: 30, height: 80)
        let texts = [StubReader.size(20, 60): "えっ", StubReader.size(30, 80): "こんにちは"]
        let pipeline = PagePipeline(
            detector: StubDetector(log: log, blocks: { region in
                [top, shared].filter { region.cgRect.contains($0.box) }
            }),
            reader: StubReader(log: log, texts: texts), translator: StubTranslator(translations: Self.translations)
        )
        let page = try PageBitmap.blank(width: 200, height: 700)
        let tiles = PageTiling().tiles(width: 200, height: 700)

        let text = try await pipeline.text(of: page)

        #expect(tiles.map(\.y0) == [0, 200, 400])
        // Every tile is detected; the block two tiles share is read once.
        #expect(log.all == ["detect 0", "detect 200", "detect 400", "read 28x68", "read 38x88"])
        #expect(text.timings.tiles == 3 && text.timings.blocksFound == 2)
        #expect(text.blocks.map(\.source) == ["えっ", "こんにちは"])
    }

    // MARK: What is stored

    @Test func thePagesTextIsStoredAsFractionsOfThePage() async throws {
        let text = try await Self.pipeline().text(of: PageBitmap.blank(width: 400, height: 300))
        let date = Date(timeIntervalSince1970: 1_000)
        let stored = text.translation(gid: "42", pageIndex: 7, modelSetKey: "k2xl768.cpt2.jmt1.t1", createdAt: date)

        #expect(stored.gid == "42" && stored.pageIndex == 7 && stored.createdAt == date)
        #expect(stored.imageWidth == 400 && stored.imageHeight == 300)
        #expect(stored.regions.count == 3 && stored.hasTranslatedText)
        #expect(stored.regions[0].box == FractionalRect(x: 0.75, y: 40.0 / 300, width: 0.075, height: 100.0 / 300))
        #expect(stored.regions[0].balloonBox != nil && stored.regions[1].balloonBox == nil)
        #expect(stored.regions.map(\.isTranslated) == [true, true, false])
    }
}
