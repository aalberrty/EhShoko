extension TensorView {
    /// Copies `count` values along the last axis of a rank-4 tensor, from (0, `channel`, `row`,
    /// `column`), into `destination`: a bulk conversion when the axis is contiguous, which it is
    /// for every mask output here.
    func copyRun(channel: Int, row: Int, column: Int, count: Int, into destination: UnsafeMutablePointer<Float>) {
        let start = channel * strides[1] + row * strides[2] + column * strides[3]
        guard strides[3] == 1 else {
            for index in 0..<count { destination[index] = value(start + index * strides[3]) }
            return
        }
        if isHalf {
            Half.widen(base + start * 2, destination, count: count)
        } else {
            destination.update(from: (base + start * 4).assumingMemoryBound(to: Float.self), count: count)
        }
    }

    /// The values of `channel` over a window of a rank-4 tensor's last two axes, row by row.
    func window(channel: Int, _ window: GridWindow) -> [Float] {
        var values = [Float](repeating: 0, count: window.width * window.height)
        values.withUnsafeMutableBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return }
            for y in 0..<window.height {
                copyRun(channel: channel, row: window.y0 + y, column: window.x0, count: window.width, into: base + y * window.width)
            }
        }
        return values
    }
}
