import CoreGraphics
import CoreML
@testable import EhPageTranslation
import Foundation
import Testing

/// A repaint model that paints every tile one colour and remembers what it was asked.
actor StubInpainter: Inpainter {
    struct Call: Sendable {
        var tile: [UInt8]
        var mask: [UInt8]
    }

    private(set) var calls: [Call] = []
    private let color: PixelColor
    private let fails: Bool

    init(color: PixelColor = PixelColor(red: 10, green: 200, blue: 30), fails: Bool = false) {
        self.color = color
        self.fails = fails
    }

    struct Failure: Error {}

    func repaint(tile: [UInt8], mask: [UInt8]) async throws -> [UInt8] {
        calls.append(Call(tile: tile, mask: mask))
        if fails { throw Failure() }
        var out = tile
        for index in 0..<(tile.count / 4) {
            out[index * 4] = color.red
            out[index * 4 + 1] = color.green
            out[index * 4 + 2] = color.blue
        }
        return out
    }
}

@Suite struct TilePlanTests {
    @Test func oneTileAroundShortText() {
        let tiles = TilePlan.tiles(for: PixelRect(x: 600, y: 400, width: 60, height: 180), pageWidth: 1400, pageHeight: 2000)
        // 1.6 times the longer side plus 32, centred on the text.
        #expect(tiles == [PixelRect(x: 470, y: 330, width: 320, height: 320)])
    }

    @Test func aSmallMaskStillGetsAnUsefulAmountOfArtwork() {
        let tiles = TilePlan.tiles(for: PixelRect(x: 500, y: 500, width: 20, height: 30), pageWidth: 1400, pageHeight: 2000)
        #expect(tiles == [PixelRect(x: 382, y: 387, width: 256, height: 256)])
    }

    @Test func aTileIsMovedOntoThePage() {
        let corner = TilePlan.tiles(for: PixelRect(x: 0, y: 0, width: 40, height: 100), pageWidth: 1000, pageHeight: 1400)
        #expect(corner == [PixelRect(x: 0, y: 0, width: 256, height: 256)])
        let far = TilePlan.tiles(for: PixelRect(x: 960, y: 1300, width: 40, height: 100), pageWidth: 1000, pageHeight: 1400)
        #expect(far == [PixelRect(x: 744, y: 1144, width: 256, height: 256)])
    }

    @Test func longTextIsCoveredByARowOfTheLargestTiles() throws {
        let mask = PixelRect(x: 300, y: 100, width: 80, height: 1500)
        let tiles = TilePlan.tiles(for: mask, pageWidth: 1400, pageHeight: 2000)
        #expect(tiles.count == 3)
        #expect(tiles.allSatisfy { $0.width == 768 && $0.height == 768 })
        #expect(tiles.first?.y0 == 36 && tiles.last?.y1 == 1664)
        for (upper, lower) in zip(tiles, tiles.dropFirst()) { #expect(upper.y1 - lower.y0 >= 128) }
        // Every pixel of the mask is inside a tile, and owned by the tile it lies deepest in.
        for y in stride(from: mask.y0, to: mask.y1, by: 7) {
            let owner = try #require(TilePlan.owner(ofX: 340, y: y, among: tiles))
            #expect(tiles[owner].contains(340, y))
        }
        #expect(TilePlan.owner(ofX: 340, y: 150, among: tiles) == 0)
        #expect(TilePlan.owner(ofX: 340, y: 1500, among: tiles) == 2)
        #expect(TilePlan.owner(ofX: 5, y: 5, among: tiles) == nil)
    }

    @Test func aPageSmallerThanATileGivesTheLargestSquareThatFits() {
        let tiles = TilePlan.tiles(for: PixelRect(x: 10, y: 10, width: 100, height: 60), pageWidth: 200, pageHeight: 150)
        #expect(tiles == [PixelRect(x: 0, y: 0, width: 150, height: 150)])
        #expect(TilePlan.tiles(for: .zero, pageWidth: 200, pageHeight: 150).isEmpty)
        #expect(TilePlan.tiles(for: PixelRect(x: 500, y: 500, width: 10, height: 10), pageWidth: 200, pageHeight: 150).isEmpty)
    }
}

@Suite struct TiledRepaintTests {
    private func page(width: Int, height: Int) throws -> PageBitmap {
        let image = try #require(SyntheticImages.page(width: width, height: height))
        return try PageBitmap(data: #require(SyntheticImages.encode(image, as: "public.png")))
    }

    /// A mask of `rect` with every other pixel set, so that pasting through it can be seen.
    private func checkerMask(_ rect: PixelRect) -> RegionMask {
        var bits = [UInt8](repeating: 0, count: rect.area)
        for y in 0..<rect.height {
            for x in 0..<rect.width where (x + y) % 2 == 0 { bits[y * rect.width + x] = 1 }
        }
        return RegionMask(rect: rect, bits: bits)
    }

    @Test func onlyTheMasksPixelsAreRepainted() async throws {
        let page = try page(width: 700, height: 900)
        let mask = checkerMask(PixelRect(x: 300, y: 380, width: 60, height: 140))
        let stub = StubInpainter()
        var canvas = PixelWindow(page: page, rect: mask.rect.insetBy(-12, -12))
        let before = canvas
        try await TiledRepaint.repaint(&canvas, page: page, mask: mask, with: stub)
        for y in canvas.rect.y0..<canvas.rect.y1 {
            for x in canvas.rect.x0..<canvas.rect.x1 {
                let color = canvas.color(canvas.index(x, y))
                if mask.contains(x, y) {
                    #expect(color == PixelColor(red: 10, green: 200, blue: 30))
                } else {
                    #expect(color == before.color(before.index(x, y)))
                }
            }
        }
        let calls = await stub.calls
        #expect(calls.count == 1)
        #expect(calls[0].tile.count == 512 * 512 * 4 && calls[0].mask.count == 512 * 512)
    }

    @Test func theModelSeesTheTileAtItsOwnSizeAndTheMaskOverTheText() async throws {
        let page = try page(width: 700, height: 900)
        // 300 pixels of text: one tile of 512 pixels, which is the model's size.
        let rect = PixelRect(x: 320, y: 300, width: 40, height: 300)
        let mask = RegionMask(rect: rect, bits: [UInt8](repeating: 1, count: rect.area))
        let stub = StubInpainter()
        var canvas = PixelWindow(page: page, rect: rect)
        try await TiledRepaint.repaint(&canvas, page: page, mask: mask, with: stub)
        let call = try #require(await stub.calls.first)
        let tile = try #require(TilePlan.tiles(for: rect, pageWidth: 700, pageHeight: 900).first)
        #expect(tile.width == 512)
        #expect(call.tile == PixelWindow(page: page, rect: tile).rgba)
        #expect(call.mask.reduce(0) { $0 + Int($1) } == rect.area)
        #expect(call.mask[(rect.y0 - tile.y0) * 512 + rect.x0 - tile.x0] == 1)
        #expect(call.mask[(rect.y0 - tile.y0 - 1) * 512 + rect.x0 - tile.x0] == 0)
    }

    @Test func aSmallerTileIsEnlargedAndItsMaskWithIt() {
        // A tile of 256 pixels: each page pixel is four cells of the model's input.
        let tile = PixelRect(x: 100, y: 100, width: 256, height: 256)
        let mask = RegionMask(rect: PixelRect(x: 110, y: 120, width: 2, height: 1), bits: [1, 1])
        let cells = TiledRepaint.modelMask(mask, tile: tile)
        #expect(cells.reduce(0) { $0 + Int($1) } == 8)
        #expect(cells[40 * 512 + 20] == 1 && cells[41 * 512 + 23] == 1 && cells[42 * 512 + 20] == 0)
        // A tile of 768 pixels: three page pixels share two cells, and none is lost.
        let large = PixelRect(x: 0, y: 0, width: 768, height: 768)
        let single = RegionMask(rect: PixelRect(x: 301, y: 500, width: 1, height: 1), bits: [1])
        #expect(TiledRepaint.modelMask(single, tile: large).reduce(0) { $0 + Int($1) } >= 1)
    }

    @Test func longTextIsRepaintedTileByTileWithEveryPixelDoneOnce() async throws {
        let page = try page(width: 900, height: 1800)
        let rect = PixelRect(x: 400, y: 100, width: 50, height: 1500)
        let mask = RegionMask(rect: rect, bits: [UInt8](repeating: 1, count: rect.area))
        let stub = StubInpainter()
        var canvas = PixelWindow(page: page, rect: rect)
        try await TiledRepaint.repaint(&canvas, page: page, mask: mask, with: stub)
        #expect(await stub.calls.count == 3)
        // Tiles of 768 pixels come back softened by the resize; the stub's colour survives it.
        for index in 0..<canvas.count {
            #expect(canvas.color(index) == PixelColor(red: 10, green: 200, blue: 30))
        }
    }

    @Test func aFailingModelThrowsAndACancelledTaskStops() async throws {
        let page = try page(width: 400, height: 400)
        let rect = PixelRect(x: 100, y: 100, width: 40, height: 80)
        let mask = RegionMask(rect: rect, bits: [UInt8](repeating: 1, count: rect.area))
        var canvas = PixelWindow(page: page, rect: rect)
        await #expect(throws: StubInpainter.Failure.self) {
            try await TiledRepaint.repaint(&canvas, page: page, mask: mask, with: StubInpainter(fails: true))
        }
        let stub = StubInpainter()
        let task = Task {
            var canvas = PixelWindow(page: page, rect: rect)
            withUnsafeCurrentTask { $0?.cancel() }
            try await TiledRepaint.repaint(&canvas, page: page, mask: mask, with: stub)
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(await stub.calls.isEmpty)
    }

    @Test func resizingATile() throws {
        let flat = [UInt8](repeating: 90, count: 256 * 256 * 4)
        let larger = try TiledRepaint.scale(flat, from: 256, to: 512)
        #expect(larger.count == 512 * 512 * 4 && larger.allSatisfy { $0 == 90 })
        #expect(try TiledRepaint.scale(flat, from: 256, to: 256) == flat)
        #expect(throws: InpainterError.resize) { try TiledRepaint.scale([1, 2, 3], from: 256, to: 512) }
    }
}

@Suite struct LamaOutputTests {
    @Test func theModelsPlanesBecomeATilesBytes() throws {
        let side = TilePlan.modelSide, count = side * side
        let output = try MLMultiArray(shape: [1, 3, NSNumber(value: side), NSNumber(value: side)], dataType: .float32)
        output.withUnsafeMutableBufferPointer(ofType: Float.self) { values, _ in
            for index in 0..<count {
                values[index] = 1
                values[count + index] = 0.5
                values[2 * count + index] = 0
            }
            // Out of range and not a number: clamped, and zero.
            values[0] = 1.7
            values[count] = -0.3
            values[2 * count] = .nan
            values[2 * count + 1] = .infinity
        }
        let pixels = try LamaInpainter.pixels(of: output)
        #expect(pixels.count == count * 4)
        #expect(Array(pixels[0..<4]) == [255, 0, 0, 255])
        #expect(Array(pixels[4..<8]) == [255, 128, 0, 255])
        #expect(Array(pixels[(count - 1) * 4..<count * 4]) == [255, 128, 0, 255])
    }

    @Test func anOutputOfAnotherShapeIsRefused() throws {
        let wrong = try MLMultiArray(shape: [1, 3, 64, 64], dataType: .float32)
        #expect(throws: InpainterError.unexpectedOutput) { try LamaInpainter.pixels(of: wrong) }
        let integers = try MLMultiArray(shape: [1, 3, 512, 512], dataType: .int32)
        #expect(throws: TensorViewError.self) { try LamaInpainter.pixels(of: integers) }
    }
}
