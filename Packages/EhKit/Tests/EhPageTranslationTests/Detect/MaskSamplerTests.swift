import CoreGraphics
@testable import EhPageTranslation
import Testing

struct MaskSamplerTests {
    /// A 6 × 6 grid over a 24 × 24 input.
    static let side = 6
    static let grid: [Float] = (0..<36).map { index in
        let x = Float(index % 6), y = Float(index / 6)
        return 2 - abs(x - 2.5) - abs(y - 2) // A diamond, positive in the middle.
    }

    static func sampler(_ letterbox: Letterbox, threshold: Float = 0, inclusive: Bool = false, margin: Double = 4) -> MaskSampler {
        MaskSampler(letterbox: letterbox, gridSide: side, threshold: threshold, inclusive: inclusive, margin: margin) { _, window in
            var values: [Float] = []
            for y in window.y0...window.y1 { for x in window.x0...window.x1 { values.append(grid[y * side + x]) } }
            return values
        }
    }

    static func detection(_ box: CGRect) -> Detection {
        Detection(box: box, inputBox: box, score: 1, label: 0, anchor: 0)
    }

    /// The research's upsampling of the grid to the input (bilinear, half-pixel centres), then
    /// the threshold: what the mask must equal when the page is the input.
    static func researchMask(input: Int, window: PixelRect) -> [UInt8] {
        let scale = Float(input) / Float(side)
        func axis(_ o: Int) -> (Int, Int, Float) {
            let c = min(max((Float(o) + 0.5) / scale - 0.5, 0), Float(side - 1))
            let i0 = Int(c)
            return (i0, min(i0 + 1, side - 1), c - Float(i0))
        }
        var bits: [UInt8] = []
        for y in window.y0..<window.y1 {
            let (r0, r1, wy) = axis(y)
            for x in window.x0..<window.x1 {
                let (c0, c1, wx) = axis(x)
                let top = grid[r0 * side + c0] * (1 - wx) + grid[r0 * side + c1] * wx
                let bottom = grid[r1 * side + c0] * (1 - wx) + grid[r1 * side + c1] * wx
                bits.append(top * (1 - wy) + bottom * wy > 0 ? 1 : 0)
            }
        }
        return bits
    }

    @Test func withThePageAsTheInputTheMaskIsTheResearchsUpsampling() {
        let letterbox = Letterbox(region: PixelRect(x: 0, y: 0, width: 24, height: 24), inputWidth: 24, inputHeight: 24, placement: .stretched)
        let detection = Self.detection(CGRect(x: 6, y: 5, width: 9, height: 8))
        let mask = Self.sampler(letterbox).mask(for: detection)
        // The box grown by 4 pixels.
        #expect(mask.rect == PixelRect(x0: 2, y0: 1, x1: 19, y1: 17))
        #expect(mask.bits == Self.researchMask(input: 24, window: mask.rect))
        #expect(mask.count > 0 && mask.count < mask.rect.area)
    }

    @Test func oneSampleAgreesWithTheWholeMaskEverywhere() {
        let letterbox = Letterbox(region: PixelRect(x: 30, y: 10, width: 50, height: 70), inputWidth: 24, inputHeight: 24, placement: .centred)
        let sampler = Self.sampler(letterbox)
        let detection = Self.detection(CGRect(x: 35, y: 20, width: 30, height: 40))
        let mask = sampler.mask(for: detection)
        for y in (mask.rect.y0 - 2)..<(mask.rect.y1 + 2) {
            for x in (mask.rect.x0 - 2)..<(mask.rect.x1 + 2) {
                #expect(sampler.contains(detection, x: x, y: y) == mask.contains(x, y), "pixel \(x), \(y)")
            }
        }
    }

    @Test func aLargerPageGetsAMaskAtItsOwnResolution() {
        // A page four times the input: the diamond is four times as large in page pixels.
        let letterbox = Letterbox(region: PixelRect(x: 0, y: 0, width: 96, height: 96), inputWidth: 24, inputHeight: 24, placement: .stretched)
        let detection = Self.detection(CGRect(x: 0, y: 0, width: 96, height: 96))
        let large = Self.sampler(letterbox).mask(for: detection)
        let small = Self.sampler(Letterbox(region: PixelRect(x: 0, y: 0, width: 24, height: 24), inputWidth: 24, inputHeight: 24, placement: .stretched))
            .mask(for: Self.detection(CGRect(x: 0, y: 0, width: 24, height: 24)))
        #expect(large.rect == PixelRect(x: 0, y: 0, width: 96, height: 96))
        let ratio = Double(large.count) / Double(small.count)
        #expect(ratio > 14 && ratio < 18)
        // The diamond's centre, between cells 2 and 3 across, on row 2 down.
        #expect(large.contains(48, 36) && !large.contains(2, 2) && !large.contains(93, 93))
    }

    @Test func thresholdsCanIncludeTheirValue() {
        let letterbox = Letterbox(region: PixelRect(x: 0, y: 0, width: 24, height: 24), inputWidth: 24, inputHeight: 24, placement: .stretched)
        let detection = Self.detection(CGRect(x: 0, y: 0, width: 24, height: 24))
        // A threshold of exactly the value at the top-left cell's centre (pixel 1, 1).
        let corner = Self.grid[0]
        #expect(Self.sampler(letterbox, threshold: corner, inclusive: true).contains(detection, x: 1, y: 1))
        #expect(!Self.sampler(letterbox, threshold: corner, inclusive: false).contains(detection, x: 1, y: 1))
    }

    @Test func nothingOutsideTheWindowIsSet() {
        let letterbox = Letterbox(region: PixelRect(x: 0, y: 0, width: 24, height: 24), inputWidth: 24, inputHeight: 24, placement: .stretched)
        let detection = Self.detection(CGRect(x: 10, y: 8, width: 2, height: 2))
        let sampler = Self.sampler(letterbox, margin: 1)
        #expect(sampler.window(for: detection) == PixelRect(x0: 9, y0: 7, x1: 13, y1: 11))
        #expect(!sampler.contains(detection, x: 13, y: 9))
    }
}
