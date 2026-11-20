import Accelerate
import Foundation

/// Something that repaints the artwork behind erased text, one tile at a time.
public protocol Inpainter: Sendable {
    /// Repaints the masked pixels of one tile.
    ///
    /// - Parameters:
    ///   - tile: `TilePlan.modelSide` squared pixels: red, green, blue and one unused byte
    ///     each, row by row, top row first, as the page stores them.
    ///   - mask: one byte for each pixel, non-zero where the tile is to be repainted.
    /// - Returns: the whole tile in the layout of `tile`. Only its masked pixels are used.
    func repaint(tile: [UInt8], mask: [UInt8]) async throws -> [UInt8]
}

public enum InpainterError: Error, Equatable {
    /// The model returned something that is not a tile.
    case unexpectedOutput
    /// A tile could not be resized to the model's size or back.
    case resize
}

/// Cuts the page into tiles around a mask, has each repainted and pastes the result back
/// through the mask, so no pixel outside it changes.
enum TiledRepaint {
    /// Repaints the pixels of `mask` in `canvas`, which must hold the mask's rectangle. The
    /// tiles are cut from `page`, so the model sees the artwork around the canvas too.
    static func repaint(
        _ canvas: inout PixelWindow, page: PageBitmap, mask: RegionMask, with inpainter: any Inpainter
    ) async throws {
        let tiles = TilePlan.tiles(for: mask.rect, pageWidth: page.width, pageHeight: page.height)
        let side = TilePlan.modelSide
        for (number, rect) in tiles.enumerated() {
            try Task.checkCancellation()
            let mine = ownedMask(mask, tile: rect, number: number, tiles: tiles)
            guard mine.contains(where: { $0 != 0 }) else { continue }
            let source = PixelWindow(page: page, rect: rect)
            let input = try scale(source.rgba, from: rect.width, to: side)
            let output = try await inpainter.repaint(tile: input, mask: modelMask(mask, tile: rect))
            guard output.count == side * side * 4 else { throw InpainterError.unexpectedOutput }
            let repainted = try scale(output, from: side, to: rect.width)
            for y in 0..<rect.height {
                for x in 0..<rect.width where mine[y * rect.width + x] != 0 {
                    let pageX = rect.x0 + x, pageY = rect.y0 + y
                    guard canvas.rect.contains(pageX, pageY) else { continue }
                    let from = (y * rect.width + x) * 4, to = canvas.index(pageX, pageY) * 4
                    canvas.rgba[to] = repainted[from]
                    canvas.rgba[to + 1] = repainted[from + 1]
                    canvas.rgba[to + 2] = repainted[from + 2]
                }
            }
        }
    }

    /// The masked pixels of `tile` that this tile, of all the tiles, repaints: a plane the
    /// size of the tile.
    private static func ownedMask(_ mask: RegionMask, tile: PixelRect, number: Int, tiles: [PixelRect]) -> [UInt8] {
        var plane = [UInt8](repeating: 0, count: tile.area)
        let shared = mask.rect.intersection(tile)
        guard !shared.isEmpty else { return plane }
        for y in shared.y0..<shared.y1 {
            for x in shared.x0..<shared.x1 where mask.contains(x, y) {
                if tiles.count == 1 || TilePlan.owner(ofX: x, y: y, among: tiles) == number {
                    plane[(y - tile.y0) * tile.width + x - tile.x0] = 1
                }
            }
        }
        return plane
    }

    /// The mask the model is given: every cell of its input that holds a masked page pixel.
    /// All of the mask inside the tile, not only what this tile repaints, so the model never
    /// takes old text for artwork.
    static func modelMask(_ mask: RegionMask, tile: PixelRect) -> [UInt8] {
        let side = TilePlan.modelSide
        var plane = [UInt8](repeating: 0, count: side * side)
        let shared = mask.rect.intersection(tile)
        guard !shared.isEmpty else { return plane }
        // A page pixel covers the cells from its near edge to its far edge.
        func cells(_ offset: Int) -> ClosedRange<Int> {
            let first = offset * side / tile.width
            let last = max(first, ((offset + 1) * side - 1) / tile.width)
            return first...min(side - 1, last)
        }
        for y in shared.y0..<shared.y1 {
            for x in shared.x0..<shared.x1 where mask.contains(x, y) {
                for cellY in cells(y - tile.y0) {
                    for cellX in cells(x - tile.x0) { plane[cellY * side + cellX] = 1 }
                }
            }
        }
        return plane
    }

    /// A square of `from` × `from` pixels (four bytes each) resampled to `to` × `to`.
    static func scale(_ pixels: [UInt8], from: Int, to: Int) throws -> [UInt8] {
        guard from != to else { return pixels }
        guard from > 0, to > 0, pixels.count == from * from * 4 else { throw InpainterError.resize }
        var scaled = [UInt8](repeating: 255, count: to * to * 4)
        let error = pixels.withUnsafeBytes { source in
            scaled.withUnsafeMutableBytes { destination in
                var input = vImage_Buffer(
                    data: UnsafeMutableRawPointer(mutating: source.baseAddress), height: vImagePixelCount(from),
                    width: vImagePixelCount(from), rowBytes: from * 4
                )
                var output = vImage_Buffer(
                    data: destination.baseAddress, height: vImagePixelCount(to), width: vImagePixelCount(to),
                    rowBytes: to * 4
                )
                return vImageScale_ARGB8888(&input, &output, nil, vImage_Flags(kvImageHighQualityResampling))
            }
        }
        guard error == kvImageNoError else { throw InpainterError.resize }
        return scaled
    }
}
