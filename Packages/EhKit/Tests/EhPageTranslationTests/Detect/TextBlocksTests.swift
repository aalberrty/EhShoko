import CoreGraphics
@testable import EhPageTranslation
import EhModels
import Testing

struct TextBlocksTests {
    static let region = PixelRect(x: 0, y: 0, width: 1000, height: 1000)

    static func detection(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat, label: Int, score: Float) -> Detection {
        let box = CGRect(x: x, y: y, width: width, height: height)
        return Detection(box: box, inputBox: box, score: score, label: label, anchor: 0)
    }

    /// RTMDet's classes: 0 balloon, 2 text, 3 other text.
    static func role(_ label: Int) -> DetectionRole { RTMDetDecoder.role(of: label) }

    /// A balloon holds the pixels of its box.
    static func group(_ detections: [Detection], linesAreBlocks: Bool) -> [TextBlocks.Group] {
        TextBlocks.group(detections, role: role, linesAreBlocks: linesAreBlocks, region: region) { balloon, x, y in
            PixelRect(covering: detections[balloon].box).contains(x, y)
        }
    }

    @Test func duplicatesAreRemovedWhateverTheirClass() {
        let detections = [
            Self.detection(100, 100, 50, 100, label: 2, score: 0.6),
            Self.detection(102, 100, 50, 100, label: 3, score: 0.9), // The same box as a sound effect.
            Self.detection(300, 100, 50, 100, label: 2, score: 0.8),
            Self.detection(330, 100, 50, 100, label: 2, score: 0.7) // Overlaps by less than 0.6.
        ]
        #expect(TextBlocks.removeDuplicates([0, 1, 2, 3], in: detections) == [1, 2, 3])
        let groups = Self.group(detections, linesAreBlocks: true)
        #expect(groups.count == 3)
        #expect(groups.filter(\.isSoundEffect).count == 1)
    }

    @Test func aBlockDetectorsBoxesAreBlocksInTheBalloonThatHoldsTheirCentre() {
        let detections = [
            Self.detection(100, 100, 300, 300, label: 0, score: 0.9),
            Self.detection(50, 50, 500, 500, label: 0, score: 0.5),
            Self.detection(200, 150, 60, 200, label: 2, score: 0.8), // In both balloons: the better one.
            Self.detection(450, 450, 40, 80, label: 2, score: 0.7), // Only in the large one.
            Self.detection(700, 700, 100, 50, label: 2, score: 0.6), // In none.
            Self.detection(300, 300, 50, 50, label: 3, score: 0.5) // A sound effect in a balloon.
        ]
        let groups = Self.group(detections, linesAreBlocks: true)
        #expect(groups.map(\.balloon) == [0, 1, nil, 0])
        #expect(groups.map(\.isSoundEffect) == [false, false, false, true])
        #expect(groups[0].isVertical && !groups[2].isVertical)
        #expect(groups[0].lines == [groups[0].box])
    }

    @Test func linesInABalloonAreClusteredRightToLeft() {
        // Three vertical columns in a balloon, a fourth column of a much larger size beside them.
        let detections = [
            Self.detection(100, 100, 400, 400, label: 0, score: 0.9),
            Self.detection(300, 150, 30, 200, label: 2, score: 0.8),
            Self.detection(200, 150, 30, 150, label: 2, score: 0.7),
            Self.detection(250, 150, 30, 250, label: 2, score: 0.6),
            Self.detection(380, 150, 90, 300, label: 2, score: 0.5)
        ]
        let groups = Self.group(detections, linesAreBlocks: false)
        #expect(groups.count == 2)
        let columns = groups[0]
        #expect(columns.balloon == 0 && columns.isVertical && !columns.isSoundEffect)
        #expect(columns.lines.map(\.minX) == [300, 250, 200])
        #expect(columns.box == CGRect(x: 200, y: 150, width: 130, height: 250))
        #expect(columns.score == 0.8)
        #expect(groups[1].lines.count == 1 && groups[1].balloon == 0)
    }

    @Test func linesOutsideBalloonsAndSoundEffectsAreClusteredWithoutBalloons() {
        let detections = [
            Self.detection(100, 100, 200, 200, label: 0, score: 0.9),
            Self.detection(600, 100, 200, 30, label: 2, score: 0.8), // Two horizontal lines…
            Self.detection(600, 140, 180, 30, label: 2, score: 0.7), // …close together.
            Self.detection(600, 600, 200, 30, label: 2, score: 0.7), // Far below.
            Self.detection(150, 150, 30, 30, label: 3, score: 0.6), // Sound effect lines in the balloon.
            Self.detection(150, 190, 30, 30, label: 3, score: 0.5)
        ]
        let groups = Self.group(detections, linesAreBlocks: false)
        #expect(groups.count == 3)
        #expect(groups[0].lines.map(\.minY) == [100, 140] && !groups[0].isVertical && groups[0].balloon == nil)
        #expect(groups[1].lines.count == 1 && groups[1].balloon == nil)
        #expect(groups[2].isSoundEffect && groups[2].lines.count == 2 && groups[2].balloon == 0)
    }

    @Test func overlappingLinesAreOneLine() {
        let detections = [
            Self.detection(100, 100, 30, 200, label: 2, score: 0.6),
            Self.detection(105, 100, 30, 150, label: 2, score: 0.9),
            Self.detection(100, 400, 30, 100, label: 2, score: 0.5)
        ]
        #expect(TextBlocks.suppressOverlappingLines([0, 1, 2], in: detections) == [1, 2])
    }

    @Test func clusteringWantsCloseLinesOfASimilarSize() {
        let detections = [
            Self.detection(0, 0, 30, 100, label: 2, score: 1),
            Self.detection(56, 0, 30, 100, label: 2, score: 1), // Gap 26 < 0.9 × 30.
            Self.detection(114, 0, 30, 100, label: 2, score: 1), // Gap 28 > 0.9 × 30: not joined.
            Self.detection(-60, 0, 41, 100, label: 2, score: 1) // Gap 19, but 41 / 30 > 1.34.
        ]
        #expect(TextBlocks.cluster([0, 1, 2, 3], in: detections) == [[0, 1], [2], [3]])
    }

    @Test func blocksComeInReadingOrder() {
        func block(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> TextBlock {
            TextBlock(box: CGRect(x: x, y: y, width: width, height: height), kind: .dialogue, isVertical: true, score: 1)
        }
        // A row of three, right to left; a block lower on the left that shares too little of the
        // row's height; a row of two below.
        let blocks = [
            block(100, 50, 50, 200), block(500, 40, 50, 220), block(300, 60, 50, 150),
            block(20, 200, 50, 200), block(100, 600, 50, 100), block(400, 620, 50, 100)
        ]
        let ordered = ReadingOrder.sorted(blocks).map(\.box.minX)
        #expect(ordered == [500, 300, 100, 20, 400, 100])
    }

    @Test func assemblyAttachesBalloonsAndKinds() {
        let detections = [
            Self.detection(100, 100, 300, 300, label: 0, score: 0.9),
            Self.detection(200, 150, 30, 200, label: 2, score: 0.8),
            Self.detection(700, 100, 30, 200, label: 2, score: 0.7),
            Self.detection(600, 800, 100, 50, label: 3, score: 0.6)
        ]
        var timings = DetectionTimings()
        let blocks = TextBlocks.assemble(
            detections, role: Self.role, linesAreBlocks: true, region: Self.region, masks: nil, timings: &timings
        )
        #expect(blocks.map(\.kind) == [.aside, .dialogue, .soundEffect])
        #expect(blocks[1].balloon == Balloon(box: CGRect(x: 100, y: 100, width: 300, height: 300)))
        #expect(blocks[0].balloon == nil && blocks[2].balloon == nil)
        #expect(blocks.map(\.score) == [0.7, 0.8, 0.6])
    }
}
