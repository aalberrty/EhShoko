/// OpenCV's `cv2.resize(…, INTER_LINEAR)` for 8-bit images, value for value: pixel centres at
/// half pixels, two taps per axis and no anti-aliasing, 11-bit fixed-point weights and the
/// rounding of OpenCV's vectorised vertical pass. An exact halving in both directions is
/// averaged over 2 × 2 pixels, as OpenCV switches to its area filter there.
///
/// Ultralytics letterboxes with it, so Koharu YOLO26s was trained on its output; Core Graphics'
/// resampling, at any quality, moved 8% of that detector's boxes.
enum BilinearResize {
    static let weightBits = 11
    static let weightScale = 1 << weightBits

    /// For one output position: the first source index and the two weights.
    struct Tap: Equatable {
        var index: Int
        var weight0: Int32
        var weight1: Int32
    }

    /// OpenCV's taps exactly: the scale as the inverse of the inverse scale, the fraction in
    /// single precision, and each weight rounded on its own, so the two may sum to one more or
    /// one less than `weightScale`.
    static func taps(source: Int, destination: Int) -> [Tap] {
        let scale = 1 / (Double(destination) / Double(source))
        return (0..<destination).map { position in
            var fraction = Float((Double(position) + 0.5) * scale - 0.5)
            var index = Int(fraction.rounded(.down))
            fraction -= Float(index)
            if index < 0 {
                index = 0
                fraction = 0
            }
            if index >= source - 1 {
                index = source - 1
                fraction = 0
            }
            let unit = Float(weightScale)
            return Tap(
                index: index, weight0: Int32(((1 - fraction) * unit).rounded(.toNearestOrEven)),
                weight1: Int32((fraction * unit).rounded(.toNearestOrEven))
            )
        }
    }

    /// Resizes the first three channels of a 4-byte-per-pixel image into a rectangle of another.
    ///
    /// - Parameters:
    ///   - source: the top-left pixel of the part to resize; rows `sourceBytesPerRow` apart.
    ///   - destination: the top-left pixel of the rectangle to fill; its fourth bytes are set to
    ///     255.
    ///   - swapsRedAndBlue: writes the source's first channel third and its third first, as
    ///     the page's red-first pixels go into a model's blue-first buffer.
    static func resize(
        source: UnsafePointer<UInt8>, width sourceWidth: Int, height sourceHeight: Int, bytesPerRow sourceBytesPerRow: Int,
        into destination: UnsafeMutablePointer<UInt8>, width: Int, height: Int, bytesPerRow: Int,
        swapsRedAndBlue: Bool
    ) {
        guard sourceWidth > 0, sourceHeight > 0, width > 0, height > 0 else { return }
        let order = swapsRedAndBlue ? (2, 1, 0) : (0, 1, 2)
        if sourceWidth == width * 2, sourceHeight == height * 2 {
            halve(source: source, bytesPerRow: sourceBytesPerRow, into: destination, width: width, height: height,
                  bytesPerRow: bytesPerRow, order: order)
            return
        }
        let columns = taps(source: sourceWidth, destination: width)
        let rows = taps(source: sourceHeight, destination: height)
        let rowLength = width * 3
        let buffer = UnsafeMutablePointer<Int32>.allocate(capacity: rowLength * 2)
        defer { buffer.deallocate() }
        var upper = buffer, lower = buffer + rowLength
        var upperRow = -1, lowerRow = -1

        // One source row filtered horizontally, in the destination's channel order.
        func filter(_ y: Int, into row: UnsafeMutablePointer<Int32>) {
            let line = source + y * sourceBytesPerRow
            for x in 0..<width {
                let tap = columns[x]
                let first = line + tap.index * 4, second = line + min(tap.index + 1, sourceWidth - 1) * 4
                let out = row + x * 3
                out[0] = Int32(first[order.0]) * tap.weight0 + Int32(second[order.0]) * tap.weight1
                out[1] = Int32(first[order.1]) * tap.weight0 + Int32(second[order.1]) * tap.weight1
                out[2] = Int32(first[order.2]) * tap.weight0 + Int32(second[order.2]) * tap.weight1
            }
        }

        for y in 0..<height {
            let tap = rows[y]
            let y0 = tap.index, y1 = min(tap.index + 1, sourceHeight - 1)
            if upperRow != y0 {
                if lowerRow == y0 {
                    swap(&upper, &lower)
                    swap(&upperRow, &lowerRow)
                } else {
                    filter(y0, into: upper)
                    upperRow = y0
                }
            }
            if lowerRow != y1 {
                filter(y1, into: lower)
                lowerRow = y1
            }
            let out = destination + y * bytesPerRow
            let weight0 = Int32(tap.weight0), weight1 = Int32(tap.weight1)
            for x in 0..<width {
                for channel in 0..<3 {
                    let index = x * 3 + channel
                    // OpenCV's VResizeLinearVec_32s8u: ((w0·(S0>>4))>>16 + (w1·(S1>>4))>>16 + 2) >> 2.
                    let value = ((weight0 &* (upper[index] >> 4)) >> 16) &+ ((weight1 &* (lower[index] >> 4)) >> 16) &+ 2
                    out[x * 4 + channel] = UInt8(clamping: value >> 2)
                }
                out[x * 4 + 3] = 255
            }
        }
    }

    /// OpenCV's area filter for an exact halving: the rounded mean of each 2 × 2 block.
    private static func halve(
        source: UnsafePointer<UInt8>, bytesPerRow sourceBytesPerRow: Int,
        into destination: UnsafeMutablePointer<UInt8>, width: Int, height: Int, bytesPerRow: Int,
        order: (Int, Int, Int)
    ) {
        let channels = [order.0, order.1, order.2]
        for y in 0..<height {
            let top = source + 2 * y * sourceBytesPerRow, bottom = top + sourceBytesPerRow
            let out = destination + y * bytesPerRow
            for x in 0..<width {
                let left = 8 * x, right = left + 4
                for (channel, from) in channels.enumerated() {
                    let sum = Int(top[left + from]) + Int(top[right + from]) + Int(bottom[left + from]) + Int(bottom[right + from])
                    out[x * 4 + channel] = UInt8((sum + 2) >> 2)
                }
                out[x * 4 + 3] = 255
            }
        }
    }
}
