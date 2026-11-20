import CoreGraphics
import Foundation

/// manga-ocr-nar-small's preprocessing (`preprocess.py` of its release): the crop scaled, its
/// shape kept, to fill as much of a grid of at most 324 patches of 14 × 14 pixels as it can;
/// the rest of the grid in the median colour of the scaled crop's border; each patch's pixels
/// normalised with CLIP's mean and deviation, channel by channel. The release resizes with
/// PIL's bicubic filter; this uses Core Graphics, which rarely changes the text.
struct NARInput: Sendable, Equatable {
    static let mean: [Float] = [0.48145466, 0.4578275, 0.40821073]
    static let deviation: [Float] = [0.26862954, 0.26130258, 0.27577711]

    /// Patches the model takes at most.
    let budget: Int
    /// A patch's side in pixels.
    let patch: Int

    /// The grid a crop of the given size fills: `rows` × `columns` patches, the crop scaled to
    /// `scaledWidth` × `scaledHeight` at its top left. The scale is the largest for which the
    /// grid has at most `budget` patches, found by bisection as the release does.
    struct Grid: Equatable {
        var rows: Int
        var columns: Int
        var scaledWidth: Int
        var scaledHeight: Int
        var count: Int { rows * columns }
    }

    func grid(width: Int, height: Int) -> Grid {
        var low = 1e-4, high = 1000.0
        let side = Double(patch)
        func patches(_ scale: Double) -> (Int, Int) {
            (Int((Double(height) * scale / side).rounded(.up)), Int((Double(width) * scale / side).rounded(.up)))
        }
        for _ in 0..<60 {
            let middle = (low + high) / 2
            let (rows, columns) = patches(middle)
            if rows * columns <= budget { low = middle } else { high = middle }
        }
        let (rows, columns) = patches(low)
        // Python's round(), half to even.
        let scaledWidth = max(1, min(columns * patch, Int((Double(width) * low).rounded(.toNearestOrEven))))
        let scaledHeight = max(1, min(rows * patch, Int((Double(height) * low).rounded(.toNearestOrEven))))
        return Grid(rows: rows, columns: columns, scaledWidth: scaledWidth, scaledHeight: scaledHeight)
    }

    /// The crop scaled to the grid's size: red, green, blue and an unused byte for each pixel,
    /// drawn in the crop's own colour space.
    func scaled(_ crop: CGImage, to grid: Grid) -> [UInt8]? {
        let width = grid.scaledWidth, height = grid.scaledHeight
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(
                data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: PageBitmap.colorSpace(for: crop), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            ) else { return false }
            context.interpolationQuality = .high
            context.draw(crop, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return drawn ? pixels : nil
    }

    /// The median of each channel over the border of the scaled crop (its first and last rows
    /// and columns, the corners counted twice, as numpy concatenates them), cut to a byte.
    static func borderMedian(_ pixels: [UInt8], width: Int, height: Int) -> [UInt8] {
        (0..<3).map { channel in
            var values: [UInt8] = []
            values.reserveCapacity(2 * (width + height))
            for x in 0..<width { values.append(pixels[x * 4 + channel]) }
            for x in 0..<width { values.append(pixels[((height - 1) * width + x) * 4 + channel]) }
            for y in 0..<height { values.append(pixels[y * width * 4 + channel]) }
            for y in 0..<height { values.append(pixels[(y * width + width - 1) * 4 + channel]) }
            values.sort()
            let middle = values.count / 2
            let median = values.count % 2 == 1
                ? Double(values[middle]) : (Double(values[middle - 1]) + Double(values[middle])) / 2
            return UInt8(median)
        }
    }

    /// The model's patch input for one crop: `budget` rows of `3 × patch × patch` values, each
    /// patch channel by channel, row by row; rows past the grid's patches are zero.
    func patches(_ pixels: [UInt8], grid: Grid) -> [Float] {
        let width = grid.scaledWidth, height = grid.scaledHeight, area = patch * patch
        let fill = Self.borderMedian(pixels, width: width, height: height)
        var values = [Float](repeating: 0, count: budget * 3 * area)
        for row in 0..<grid.rows {
            for column in 0..<grid.columns {
                let base = (row * grid.columns + column) * 3 * area
                for channel in 0..<3 {
                    let mean = Self.mean[channel], deviation = Self.deviation[channel]
                    let background = (Float(fill[channel]) / 255 - mean) / deviation
                    for py in 0..<patch {
                        let y = row * patch + py
                        for px in 0..<patch {
                            let x = column * patch + px
                            values[base + channel * area + py * patch + px] = y < height && x < width
                                ? (Float(pixels[(y * width + x) * 4 + channel]) / 255 - mean) / deviation
                                : background
                        }
                    }
                }
            }
        }
        return values
    }
}
