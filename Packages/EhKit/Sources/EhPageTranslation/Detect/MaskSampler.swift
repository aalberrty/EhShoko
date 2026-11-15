import CoreGraphics

/// A window of cells of a mask output grid, inclusive at both ends.
struct GridWindow: Equatable {
    var x0: Int, y0: Int, x1: Int, y1: Int
    var width: Int { x1 - x0 + 1 }
    var height: Int { y1 - y0 + 1 }
}

/// Turns a network's low-resolution mask output into masks in page-bitmap pixels.
///
/// The networks give a grid of values over their square input (the 2XL's mask logits, YOLO's
/// prototype products, RTMDet's dynamic-convolution logits). A page pixel is set where the
/// grid, sampled bilinearly with half-pixel centres at that pixel's centre in the input, passes
/// the threshold. With the page as the input this is the research's upsampling exactly; for a
/// real page it is one bilinear step from the grid to page pixels, never through the input's
/// pixels.
struct MaskSampler {
    let letterbox: Letterbox
    /// Cells along each side of the input.
    let gridSide: Int
    let threshold: Float
    /// Whether a value equal to the threshold is set.
    let inclusive: Bool
    /// Input pixels kept around a detection's box.
    let margin: Double
    /// The values of a detection's cells in a window, row by row.
    let cells: (_ detection: Detection, _ window: GridWindow) -> [Float]

    struct Tap {
        var index0: Int
        var index1: Int
        var weight: Float
    }

    /// The page pixels a detection's mask covers: its box grown by the margin, cut to the region.
    func window(for detection: Detection) -> PixelRect {
        let grown = detection.box.insetBy(dx: -margin / letterbox.scaleX, dy: -margin / letterbox.scaleY)
        return PixelRect(covering: grown).intersection(letterbox.region)
    }

    /// The grid position sampled for input position `input`.
    @inline(__always)
    private func tap(input: Double, inputSide: Int) -> Tap {
        let scale = Float(inputSide) / Float(gridSide)
        let position = min(max(Float(input) / scale - 0.5, 0), Float(gridSide - 1))
        let index0 = Int(position)
        return Tap(index0: index0, index1: min(index0 + 1, gridSide - 1), weight: position - Float(index0))
    }

    @inline(__always)
    private func isSet(_ value: Float) -> Bool {
        inclusive ? value >= threshold : value > threshold
    }

    /// Whether the mask of `detection` holds page pixel (`x`, `y`): one sample, the same as the
    /// whole mask gives there.
    func contains(_ detection: Detection, x: Int, y: Int) -> Bool {
        guard window(for: detection).contains(x, y) else { return false }
        let column = tap(input: letterbox.inputX(ofPixel: x), inputSide: letterbox.inputWidth)
        let row = tap(input: letterbox.inputY(ofPixel: y), inputSide: letterbox.inputHeight)
        let grid = GridWindow(x0: column.index0, y0: row.index0, x1: column.index1, y1: row.index1)
        let values = cells(detection, grid)
        guard values.count == grid.width * grid.height else { return false }
        let right = grid.width - 1, below = grid.width * (grid.height - 1)
        let top = values[0] * (1 - column.weight) + values[right] * column.weight
        let bottom = values[below] * (1 - column.weight) + values[below + right] * column.weight
        return isSet(top * (1 - row.weight) + bottom * row.weight)
    }

    /// The mask of `detection` over its window.
    func mask(for detection: Detection) -> RegionMask {
        let rect = window(for: detection)
        guard !rect.isEmpty else { return RegionMask(rect: .zero) }
        let columns = (rect.x0..<rect.x1).map { tap(input: letterbox.inputX(ofPixel: $0), inputSide: letterbox.inputWidth) }
        let rows = (rect.y0..<rect.y1).map { tap(input: letterbox.inputY(ofPixel: $0), inputSide: letterbox.inputHeight) }
        guard let firstColumn = columns.first, let lastColumn = columns.last,
              let firstRow = rows.first, let lastRow = rows.last
        else { return RegionMask(rect: .zero) }
        let grid = GridWindow(x0: firstColumn.index0, y0: firstRow.index0, x1: lastColumn.index1, y1: lastRow.index1)
        let values = cells(detection, grid)
        guard values.count == grid.width * grid.height else { return RegionMask(rect: rect) }

        let width = rect.width
        var bits = [UInt8](repeating: 0, count: rect.area)
        // Each grid row the mask reads, interpolated along x once.
        var filtered = [Float](repeating: 0, count: grid.height * width)
        var isFiltered = [Bool](repeating: false, count: grid.height)
        values.withUnsafeBufferPointer { values in
            filtered.withUnsafeMutableBufferPointer { filtered in
                func filter(_ row: Int) {
                    guard !isFiltered[row] else { return }
                    isFiltered[row] = true
                    let source = row * grid.width, target = row * width
                    for (x, column) in columns.enumerated() {
                        let a = values[source + column.index0 - grid.x0], b = values[source + column.index1 - grid.x0]
                        filtered[target + x] = a * (1 - column.weight) + b * column.weight
                    }
                }
                bits.withUnsafeMutableBufferPointer { bits in
                    for (y, row) in rows.enumerated() {
                        let upper = row.index0 - grid.y0, lower = row.index1 - grid.y0
                        filter(upper)
                        filter(lower)
                        let a = upper * width, b = lower * width, out = y * width
                        let weight = row.weight
                        for x in 0..<width {
                            let value = filtered[a + x] * (1 - weight) + filtered[b + x] * weight
                            bits[out + x] = isSet(value) ? 1 : 0
                        }
                    }
                }
            }
        }
        return RegionMask(rect: rect, bits: bits)
    }
}
