import CoreGraphics
import EhModels
import Foundation

/// Stages 1 to 4 for one page: find the text, group it into blocks, read each block and
/// translate what was read.
///
/// The pipeline holds the three loaded models and nothing that changes. Each is `Sendable`
/// and does its work off the actor that awaits it, so the pipeline is a value: whoever owns
/// it (the translation service) decides how many pages run at once. Drawing is the other
/// half, `PageDrawer`, and needs none of these models.
public struct PagePipeline: Sendable {
    public var detector: any TextDetector
    public var reader: any TextReader
    public var translator: any PageTranslator
    public var rules: PipelineRules
    /// How long each model took to load, when the pipeline was loaded from files.
    public var loadTimings = PipelineLoadTimings()

    public init(
        detector: any TextDetector, reader: any TextReader, translator: any PageTranslator,
        rules: PipelineRules = PipelineRules()
    ) {
        self.detector = detector
        self.reader = reader
        self.translator = translator
        self.rules = rules
    }

    /// Finds, reads and translates the text of `page`.
    ///
    /// Cancellation is looked for before each detector call, before each block is read and
    /// before translating; the translators look for it between lines themselves. A model call
    /// that is under way cannot be interrupted, so a cancelled page stops after at most one of
    /// them and throws `CancellationError`.
    ///
    /// - Parameter onStage: called as each stage ends, for signposts and tests.
    public func text(
        of page: PageBitmap, onStage: (@Sendable (PipelineStage) -> Void)? = nil
    ) async throws -> PageText {
        let clock = ContinuousClock()
        var timings = PageTextTimings()

        // Stages 1 and 2: the detector, on the page or on each tile of a tall one.
        let tiles = rules.tiling.tiles(width: page.width, height: page.height)
        timings.tiles = tiles.count
        var found: [[TextBlock]] = []
        for tile in tiles {
            try Task.checkCancellation()
            let detected = try await detector.detect(page, in: tile)
            timings.detection += detected.timings
            found.append(detected.blocks)
        }
        var blocks = tiles.count == 1 ? found[0] : PageTiling.merge(found, tiles: tiles)
        for index in blocks.indices {
            blocks[index].kind = rules.kind(of: blocks[index])
        }
        timings.blocksFound = blocks.count
        onStage?(.found(blocks: blocks.count))

        // Stage 3: each block on its own. One that reads as nothing is dropped.
        var start = clock.now
        var kept: [TextBlock] = []
        kept.reserveCapacity(blocks.count)
        for var block in blocks {
            guard rules.kindsRead.contains(block.kind) else {
                kept.append(block)
                continue
            }
            try Task.checkCancellation()
            timings.blocksRead += 1
            let source = try await reader.read(block, on: page)
            guard !source.allSatisfy(\.isWhitespace) else {
                timings.emptyReadings += 1
                continue
            }
            block.source = source
            kept.append(block)
        }
        // Two readings of one drawn effect, or an effect across a line, would be lettered
        // over each other.
        let overlapping = rules.soundEffectsOnOtherBlocks(in: kept)
        if !overlapping.isEmpty {
            kept = kept.indices.filter { !overlapping.contains($0) }.map { kept[$0] }
            timings.overlappingSoundEffects = overlapping.count
        }
        timings.reading = clock.now - start
        onStage?(.read(blocks: timings.blocksRead - timings.emptyReadings - timings.overlappingSoundEffects))

        // Stage 4: the page's lines in one call. A line the translator gives nothing for
        // loses its block.
        try Task.checkCancellation()
        start = clock.now
        let lineIndices = kept.indices.filter { rules.kindsRead.contains(kept[$0].kind) }
        let lines = lineIndices.map { kept[$0].source }
        let translations = lines.isEmpty ? [] : try await translator.translate(lines)
        guard translations.count == lines.count else {
            throw PagePipelineError.lineCountMismatch(lines: lines.count, translations: translations.count)
        }
        var untranslated = Set<Int>()
        for (index, translation) in zip(lineIndices, translations) {
            if let translation, !translation.allSatisfy(\.isWhitespace) {
                kept[index].translation = translation
            } else {
                untranslated.insert(index)
            }
        }
        timings.untranslatedLines = untranslated.count
        let result = kept.indices.filter { !untranslated.contains($0) }.map { kept[$0] }
        timings.translating = clock.now - start
        onStage?(.translated(blocks: lines.count - untranslated.count))

        return PageText(imageWidth: page.width, imageHeight: page.height, blocks: result, timings: timings)
    }
}

/// The pipeline's own rules: which blocks are read, and how a tall page is cut.
public struct PipelineRules: Sendable, Equatable {
    /// The kinds of block that are read and translated. Every other block (sound effects,
    /// unless the switch for them is on) is kept with the page's result, unread, so a later
    /// layer can use its box.
    public var kindsRead: Set<RegionKind>
    /// Reads a box the detector calls a sound effect as dialogue when its centre lies in a
    /// balloon. The default detector labels about a fifth of the dialogue it finds a sound
    /// effect; the few of those that stand in a balloon are read this way, the notes outside
    /// balloons are not.
    public var readsSoundEffectsInBalloons: Bool
    /// While sound effects are read, drops one that lies mostly on another block that is
    /// read (`soundEffectsOnOtherBlocks(in:)`).
    public var dropsOverlappingSoundEffects: Bool
    public var tiling: PageTiling

    public init(
        kindsRead: Set<RegionKind> = [.dialogue, .aside, .caption],
        readsSoundEffectsInBalloons: Bool = PipelineRules.readsSoundEffectsInBalloonsByDefault,
        dropsOverlappingSoundEffects: Bool = true,
        tiling: PageTiling = PageTiling()
    ) {
        self.kindsRead = kindsRead
        self.readsSoundEffectsInBalloons = readsSoundEffectsInBalloons
        self.dropsOverlappingSoundEffects = dropsOverlappingSoundEffects
        self.tiling = tiling
    }

    /// The rules pages are translated by with `modelSet`: text is read, and drawn sound
    /// effects too when its switch for them is on and its detector tells them apart.
    public init(_ modelSet: PageTranslationModelSet, tiling: PageTiling = PageTiling()) {
        self.init(kindsRead: modelSet.readsSoundEffects ? Self.everyKind : Self.textKinds, tiling: tiling)
    }

    /// Text in balloons, outside them and in caption boxes: what is read with the switch off.
    public static let textKinds: Set<RegionKind> = [.dialogue, .aside, .caption]
    /// Every box the detector finds, sound effects too.
    public static let everyKind = Set(RegionKind.allCases)

    /// The kind a block the detector found is read and drawn as: a sound effect whose centre
    /// lies in a balloon is dialogue under the balloon rule, every other block keeps its own.
    public func kind(of block: TextBlock) -> RegionKind {
        readsSoundEffectsInBalloons && block.kind == .soundEffect && block.balloon != nil ? .dialogue : block.kind
    }

    /// Whether a block the detector found is read and translated.
    public func reads(_ block: TextBlock) -> Bool {
        kindsRead.contains(kind(of: block))
    }

    /// Whether the balloon rule is on. It is kept because it gains lines and loses none:
    /// on the test pages, with the default detector, 4 more lines are read exactly with CPT
    /// v2 (5 with nar-small) and none fewer. The opt-in tier (`PipelinePrivateTests`) scores
    /// it again and fails if that stops being true. Its cost: a drawn sound effect that
    /// stands in a balloon is read and lettered like dialogue.
    public static let readsSoundEffectsInBalloonsByDefault = true
}

/// A stage of `PagePipeline.text(of:)` that has just ended.
public enum PipelineStage: Sendable, Equatable {
    /// Stages 1 and 2: `blocks` were found, sound effects among them.
    case found(blocks: Int)
    /// Stage 3: `blocks` have a reading.
    case read(blocks: Int)
    /// Stage 4: `blocks` have a translation.
    case translated(blocks: Int)
}

public enum PagePipelineError: Error, Equatable {
    /// A translator must return one result for each line it was given.
    case lineCountMismatch(lines: Int, translations: Int)
}
