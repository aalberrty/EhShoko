import CoreGraphics
import CoreML
@testable import EhPageTranslation
import EhModels
import Foundation
import Synchronization
import Testing

struct NARReaderTests {
    static let input = NARInput(budget: 324, patch: 14)

    /// Grids recorded from the release's `pad_grid` (Python) for crops of these sizes.
    @Test(arguments: [
        (60, 300, NARInput.Grid(rows: 40, columns: 8, scaledWidth: 112, scaledHeight: 560)),
        (300, 60, NARInput.Grid(rows: 8, columns: 40, scaledWidth: 560, scaledHeight: 112)),
        (100, 100, NARInput.Grid(rows: 18, columns: 18, scaledWidth: 252, scaledHeight: 252)),
        (37, 412, NARInput.Grid(rows: 56, columns: 5, scaledWidth: 70, scaledHeight: 779)),
        (8, 8, NARInput.Grid(rows: 18, columns: 18, scaledWidth: 252, scaledHeight: 252)),
        (1000, 20, NARInput.Grid(rows: 3, columns: 108, scaledWidth: 1512, scaledHeight: 30))
    ])
    func theGridIsTheReleases(width: Int, height: Int, grid: NARInput.Grid) {
        let found = Self.input.grid(width: width, height: height)
        #expect(found == grid)
        #expect(found.count <= 324)
    }

    @Test func theBorderMedianCountsTheCornersTwiceAndTruncates() {
        // A 3 × 2 image: the border is every pixel; channel 0 values 10, 20, 30 / 40, 50, 61.
        let values: [UInt8] = [10, 20, 30, 40, 50, 61]
        let pixels: [UInt8] = values.flatMap { [$0, 200, 0, 255] as [UInt8] }
        // Rows: 10 20 30 40 50 61; columns: 10 40 30 61 → sorted 10 10 20 30 30 40 40 50 61 61.
        #expect(NARInput.borderMedian(pixels, width: 3, height: 2) == [35, 200, 0])
        #expect(NARInput.borderMedian([9, 8, 7, 255], width: 1, height: 1) == [9, 8, 7])
    }

    @Test func patchesAreLaidOutChannelByChannelAndPaddedWithTheBorderColour() {
        let input = NARInput(budget: 6, patch: 2)
        // A 3 × 2 image in a grid of 1 × 2 patches of 2 × 2: the fourth column is padding.
        let grid = NARInput.Grid(rows: 1, columns: 2, scaledWidth: 3, scaledHeight: 2)
        let reds: [UInt8] = [0, 51, 102, 153, 204, 255]
        let pixels: [UInt8] = reds.flatMap { [$0, 0, 255, 255] as [UInt8] }
        let values = input.patches(pixels, grid: grid)
        #expect(values.count == 6 * 12)
        func normalised(_ value: UInt8, _ channel: Int) -> Float {
            (Float(value) / 255 - NARInput.mean[channel]) / NARInput.deviation[channel]
        }
        // The first patch's red values: (0, 51) on the first row, (153, 204) on the second.
        #expect(Array(values[0..<4]) == [normalised(0, 0), normalised(51, 0), normalised(153, 0), normalised(204, 0)])
        #expect(values[4] == normalised(0, 1) && values[8] == normalised(255, 2))
        // The second patch: 102 and 255, then the border's median red.
        let fill = NARInput.borderMedian(pixels, width: 3, height: 2)[0]
        #expect(Array(values[12..<16]) == [normalised(102, 0), normalised(fill, 0), normalised(255, 0), normalised(fill, 0)])
        #expect(values[24...].allSatisfy { $0 == 0 })
    }

    @Test func theInputsMarkWhichPatchesAreRealAndWhereTheyAre() throws {
        let grid = NARInput.Grid(rows: 2, columns: 3, scaledWidth: 42, scaledHeight: 28)
        let features = try NARReader.inputs(
            patches: [Float](repeating: 0.5, count: 10 * 12), grid: grid, budget: 10, patchType: .float32
        )
        func integers(_ name: String) throws -> [Int] {
            let array = try #require(features[name]?.multiArrayValue)
            return (0..<array.count).map { array[$0].intValue }
        }
        #expect(try integers("V") == [1, 1, 1, 1, 1, 1, 0, 0, 0, 0])
        #expect(try integers("R") == [0, 0, 0, 1, 1, 1, 0, 0, 0, 0])
        #expect(try integers("C") == [0, 1, 2, 0, 1, 2, 0, 0, 0, 0])
        #expect(try integers("H") == [2] && integers("W") == [3])
        let patches = try #require(features["P"]?.multiArrayValue)
        #expect(patches.shape == [1, 10, 12] && patches[7].floatValue == 0.5)
        let half = try NARReader.inputs(patches: [Float](repeating: 0.5, count: 10 * 12), grid: grid, budget: 10, patchType: .float16)
        #expect(half["P"]?.multiArrayValue?.dataType == .float16)
        #expect(half["P"]?.multiArrayValue?[100].floatValue == 0.5)
    }

    @Test func idsAreDecodedUpToTheFirstEndOfText() throws {
        let characters = ["あ", "い", "う", "！"]
        #expect(NARReader.text([0, 1, 3, 4, 2, 2], characters: characters) == "あい！")
        #expect(NARReader.text([2, 9, 0], characters: characters) == "うあ")
        #expect(NARReader.text([4], characters: characters).isEmpty)
        let ids = try MLMultiArray(shape: [1, 5], dataType: .int32)
        for (index, value) in [3, 1, 4, 1, 5].enumerated() { ids[index] = NSNumber(value: value) }
        #expect(try NARReader.ids(ids) == [3, 1, 4, 1, 5])
    }
}

struct TextReaderTests {
    /// Records the size of every crop it is given.
    final class Recorder: TextReader {
        let sizes = Mutex<[[Int]]>([])
        var choice: TextReaderChoice { .cpt2 }
        func read(_ crop: CGImage) async throws -> String {
            sizes.withLock { $0.append([crop.width, crop.height]) }
            return "読"
        }
    }

    @Test func aBlockIsReadWithFourPixelsAroundItCutToThePage() async throws {
        let page = try PageBitmap(
            width: 100, height: 80, originalWidth: 100, originalHeight: 80,
            pixels: Data(count: 100 * 80 * 4), colorSpace: SyntheticImages.sRGB
        )
        let reader = Recorder()
        let inside = TextBlock(box: CGRect(x: 10, y: 10, width: 20, height: 30), kind: .dialogue, isVertical: true, score: 1)
        let edge = TextBlock(box: CGRect(x: 90, y: 2, width: 10, height: 20.5), kind: .aside, isVertical: true, score: 1)
        let outside = TextBlock(box: CGRect(x: 200, y: 200, width: 10, height: 10), kind: .aside, isVertical: true, score: 1)
        #expect(try await reader.read(inside, on: page) == "読")
        _ = try await reader.read(edge, on: page)
        #expect(try await reader.read(outside, on: page).isEmpty)
        #expect(reader.sizes.withLock { $0 } == [[28, 38], [14, 27]])
    }

    @Test func theReadersRunOnTheNeuralEngineAndTheDetectorsWhereTheResearchFoundThemBest() {
        #expect(TextReaders.preferredComputeUnits(for: .cpt2) == .cpuAndNeuralEngine)
        #expect(TextReaders.preferredComputeUnits(for: .narSmall) == .cpuAndNeuralEngine)
        #expect(TextDetectors.preferredComputeUnits(for: .k2xl) == .cpuAndNeuralEngine)
        #expect(TextDetectors.preferredComputeUnits(for: .v4s) == .cpuOnly)
    }
}
