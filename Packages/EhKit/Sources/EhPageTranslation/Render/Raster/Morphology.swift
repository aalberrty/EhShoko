/// Binary morphology on planes of one byte per pixel (non-zero = set), `width` × `height`,
/// row by row. The loops run on unsafe buffers: they are the inner loops of drawing a page.
enum Morphology {
    /// The squared distance from every pixel to the nearest pixel that is set (or, with
    /// `toSet` false, the nearest that is not), in linear time (Felzenszwalb and Huttenlocher).
    ///
    /// The plane is binary, so the first of the two passes, down the columns, is two sweeps
    /// that count the rows since the last feature; only the pass along the rows needs the
    /// lower envelope of parabolas.
    static func squaredDistance(_ plane: [UInt8], width: Int, height: Int, toSet: Bool = true) -> [Float] {
        let infinity: Float = 1e20
        var distance = [Float](repeating: infinity, count: width * height)
        guard width > 0, height > 0 else { return distance }
        let far = Int32(1 << 20)
        var rowsSince = [Int32](repeating: far, count: width)
        var values = [Float](repeating: 0, count: width), result = [Float](repeating: 0, count: width)
        var parabolas = [Int](repeating: 0, count: width), bounds = [Float](repeating: 0, count: width + 1)
        plane.withUnsafeBufferPointer { bits in
            distance.withUnsafeMutableBufferPointer { grid in
                rowsSince.withUnsafeMutableBufferPointer { since in
                    for y in 0..<height {
                        let row = y * width
                        for x in 0..<width {
                            if (bits[row + x] != 0) == toSet {
                                since[x] = 0
                            } else if since[x] < far {
                                since[x] += 1
                            }
                            if since[x] < far { grid[row + x] = Float(since[x] * since[x]) }
                        }
                    }
                    for x in 0..<width { since[x] = far }
                    for y in stride(from: height - 1, through: 0, by: -1) {
                        let row = y * width
                        for x in 0..<width {
                            if (bits[row + x] != 0) == toSet {
                                since[x] = 0
                            } else if since[x] < far {
                                since[x] += 1
                                let below = Float(since[x] * since[x])
                                if below < grid[row + x] { grid[row + x] = below }
                            }
                        }
                    }
                }
                values.withUnsafeMutableBufferPointer { f in
                    result.withUnsafeMutableBufferPointer { d in
                        parabolas.withUnsafeMutableBufferPointer { v in
                            bounds.withUnsafeMutableBufferPointer { z in
                                for y in 0..<height {
                                    let row = y * width
                                    for x in 0..<width { f[x] = grid[row + x] }
                                    lowerEnvelope(f, d, v, z, count: width, infinity: infinity)
                                    for x in 0..<width { grid[row + x] = d[x] }
                                }
                            }
                        }
                    }
                }
            }
        }
        return distance
    }

    /// One pass of the distance transform along a row or a column.
    @inline(__always)
    private static func lowerEnvelope(
        _ f: UnsafeMutableBufferPointer<Float>, _ d: UnsafeMutableBufferPointer<Float>,
        _ v: UnsafeMutableBufferPointer<Int>, _ z: UnsafeMutableBufferPointer<Float>, count: Int, infinity: Float
    ) {
        var k = 0
        v[0] = 0
        z[0] = -infinity
        z[1] = infinity
        if count > 1 {
            for q in 1..<count {
                let fq = f[q] + Float(q * q)
                var s = (fq - (f[v[k]] + Float(v[k] * v[k]))) / Float(2 * (q - v[k]))
                while s <= z[k], k > 0 {
                    k -= 1
                    s = (fq - (f[v[k]] + Float(v[k] * v[k]))) / Float(2 * (q - v[k]))
                }
                k += 1
                v[k] = q
                z[k] = s
                z[k + 1] = infinity
            }
        }
        k = 0
        for q in 0..<count {
            while z[k + 1] < Float(q) { k += 1 }
            let offset = q - v[k]
            d[q] = Float(offset * offset) + f[v[k]]
        }
    }

    /// Grows the set pixels by `radius` (a disc).
    static func dilate(_ plane: [UInt8], width: Int, height: Int, radius: Double) -> [UInt8] {
        guard radius > 0 else { return plane }
        let limit = Float(radius * radius)
        return squaredDistance(plane, width: width, height: height).map { $0 <= limit ? 1 : 0 }
    }

    /// Shrinks the set pixels by `radius` (a disc).
    static func erode(_ plane: [UInt8], width: Int, height: Int, radius: Double) -> [UInt8] {
        guard radius > 0 else { return plane }
        let limit = Float(radius * radius)
        let distance = squaredDistance(plane, width: width, height: height, toSet: false)
        var out = [UInt8](repeating: 0, count: plane.count)
        for index in 0..<plane.count where plane[index] != 0 && distance[index] > limit { out[index] = 1 }
        return out
    }

    /// Grows the set pixels by `radius` pixels along both axes (a square): cheaper than a
    /// disc, and enough to close the gaps of an anti-aliased outline.
    static func dilateSquare(_ plane: [UInt8], width: Int, height: Int, radius: Int) -> [UInt8] {
        guard radius > 0, width > 0, height > 0 else { return plane }
        var rows = [UInt8](repeating: 0, count: plane.count), out = [UInt8](repeating: 0, count: plane.count)
        plane.withUnsafeBufferPointer { source in
            rows.withUnsafeMutableBufferPointer { grown in
                for y in 0..<height {
                    let row = y * width
                    for x in 0..<width where source[row + x] != 0 {
                        for near in max(0, x - radius)...min(width - 1, x + radius) { grown[row + near] = 1 }
                    }
                }
            }
        }
        rows.withUnsafeBufferPointer { source in
            out.withUnsafeMutableBufferPointer { grown in
                for y in 0..<height {
                    let row = y * width
                    for x in 0..<width where source[row + x] != 0 {
                        for near in max(0, y - radius)...min(height - 1, y + radius) { grown[near * width + x] = 1 }
                    }
                }
            }
        }
        return out
    }

    /// Sets every unset pixel that cannot reach the plane's edge through unset pixels.
    static func fillHoles(_ plane: [UInt8], width: Int, height: Int) -> [UInt8] {
        guard width > 0, height > 0 else { return plane }
        var outside = [UInt8](repeating: 0, count: plane.count)
        var stack: [Int32] = []
        plane.withUnsafeBufferPointer { bits in
            outside.withUnsafeMutableBufferPointer { reached in
                func visit(_ index: Int) {
                    if bits[index] == 0, reached[index] == 0 {
                        reached[index] = 1
                        stack.append(Int32(index))
                    }
                }
                for x in 0..<width {
                    visit(x)
                    visit((height - 1) * width + x)
                }
                for y in 0..<height {
                    visit(y * width)
                    visit(y * width + width - 1)
                }
                while let next = stack.popLast() {
                    let index = Int(next), x = index % width, y = index / width
                    if x > 0 { visit(index - 1) }
                    if x < width - 1 { visit(index + 1) }
                    if y > 0 { visit(index - width) }
                    if y < height - 1 { visit(index + width) }
                }
            }
        }
        return outside.map { $0 == 0 ? 1 : 0 }
    }

    /// A connected group of set pixels: their indices and bounds within the plane.
    struct Component {
        var pixels: [Int32]
        var bounds: PixelRect
    }

    /// The groups of set pixels that touch along an edge or, with `diagonals`, a corner.
    static func components(_ plane: [UInt8], width: Int, height: Int, diagonals: Bool = true) -> [Component] {
        var seen = [UInt8](repeating: 0, count: plane.count)
        var out: [Component] = []
        var stack: [Int32] = []
        plane.withUnsafeBufferPointer { bits in
            seen.withUnsafeMutableBufferPointer { marks in
                for start in 0..<bits.count where bits[start] != 0 && marks[start] == 0 {
                    var pixels: [Int32] = []
                    var x0 = width, y0 = height, x1 = 0, y1 = 0
                    marks[start] = 1
                    stack.append(Int32(start))
                    while let next = stack.popLast() {
                        let index = Int(next), x = index % width, y = index / width
                        pixels.append(next)
                        x0 = min(x0, x)
                        x1 = max(x1, x + 1)
                        y0 = min(y0, y)
                        y1 = max(y1, y + 1)
                        for dy in -1...1 where y + dy >= 0 && y + dy < height {
                            for dx in -1...1 where x + dx >= 0 && x + dx < width {
                                if !diagonals, dx != 0, dy != 0 { continue }
                                let near = (y + dy) * width + x + dx
                                if bits[near] != 0, marks[near] == 0 {
                                    marks[near] = 1
                                    stack.append(Int32(near))
                                }
                            }
                        }
                    }
                    out.append(Component(pixels: pixels, bounds: PixelRect(x0: x0, y0: y0, x1: x1, y1: y1)))
                }
            }
        }
        return out
    }

    /// The number of set pixels.
    static func count(_ plane: [UInt8]) -> Int {
        plane.withUnsafeBufferPointer { bits in
            var total = 0
            for bit in bits where bit != 0 { total += 1 }
            return total
        }
    }
}
