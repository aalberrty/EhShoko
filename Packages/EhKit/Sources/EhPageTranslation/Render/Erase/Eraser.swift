/// Erasing without a model: the push–pull fill.
enum Eraser {
    /// Fills the pixels of `mask` in `canvas` from the pixels around them that are known: not
    /// in the mask and, when `known` is given, inside it (a balloon's interior, so that its
    /// outline and the artwork beyond never bleed into the fill).
    ///
    /// The known pixels are averaged down a pyramid and the unknown ones are filled back up
    /// from it: a smooth interpolation that keeps a balloon's gradient and needs no model. It
    /// keeps no texture, so over artwork it smears lines and screentone.
    static func pushPull(_ canvas: inout PixelWindow, mask: RegionMask, known: RegionMask? = nil, margin: Int = 12) {
        let area = mask.rect.insetBy(-margin, -margin).intersection(canvas.rect)
        guard !area.isEmpty else { return }
        var level = Level(width: area.width, height: area.height)
        for y in 0..<area.height {
            for x in 0..<area.width {
                let pageX = x + area.x0, pageY = y + area.y0
                let color = canvas.color(canvas.index(pageX, pageY))
                level.color[y * area.width + x] = SIMD3(Float(color.red), Float(color.green), Float(color.blue))
                let isKnown = !mask.contains(pageX, pageY) && (known?.contains(pageX, pageY) ?? true)
                level.weight[y * area.width + x] = isKnown ? 1 : 0
            }
        }
        var levels = [level]
        while let last = levels.last, last.width > 1 || last.height > 1 { levels.append(last.halved()) }
        for index in stride(from: levels.count - 2, through: 0, by: -1) {
            levels[index].fill(from: levels[index + 1])
        }
        let filled = levels[0]
        for y in 0..<area.height {
            for x in 0..<area.width where mask.contains(x + area.x0, y + area.y0) {
                let value = filled.color[y * area.width + x]
                canvas.set(canvas.index(x + area.x0, y + area.y0), PixelColor(
                    red: Self.byte(value.x), green: Self.byte(value.y), blue: Self.byte(value.z)
                ))
            }
        }
    }

    @inline(__always)
    private static func byte(_ value: Float) -> UInt8 {
        UInt8(min(255, max(0, value.rounded())))
    }

    /// One level of the pyramid: a colour for each pixel and how much of it is known (0 to 1).
    private struct Level {
        var width: Int
        var height: Int
        var color: [SIMD3<Float>]
        var weight: [Float]

        init(width: Int, height: Int) {
            self.width = width
            self.height = height
            color = [SIMD3<Float>](repeating: .zero, count: width * height)
            weight = [Float](repeating: 0, count: width * height)
        }

        /// The level half the size: each pixel the weighted mean of the four under it.
        func halved() -> Level {
            var out = Level(width: (width + 1) / 2, height: (height + 1) / 2)
            color.withUnsafeBufferPointer { colors in
                weight.withUnsafeBufferPointer { weights in
                    for y in 0..<out.height {
                        for x in 0..<out.width {
                            var sum = SIMD3<Float>.zero, total: Float = 0
                            for dy in 0..<2 where 2 * y + dy < height {
                                for dx in 0..<2 where 2 * x + dx < width {
                                    let index = (2 * y + dy) * width + 2 * x + dx
                                    sum += colors[index] * weights[index]
                                    total += weights[index]
                                }
                            }
                            if total > 0 { out.color[y * out.width + x] = sum / total }
                            out.weight[y * out.width + x] = min(1, total)
                        }
                    }
                }
            }
            return out
        }

        /// Fills what is unknown here from `coarser`, the level half this size, sampled
        /// bilinearly.
        mutating func fill(from coarser: Level) {
            let width = width, height = height
            coarser.color.withUnsafeBufferPointer { coarse in
                color.withUnsafeMutableBufferPointer { colors in
                    weight.withUnsafeMutableBufferPointer { weights in
                        for y in 0..<height {
                            let sy = min(max((Float(y) + 0.5) / 2 - 0.5, 0), Float(coarser.height - 1))
                            let y0 = Int(sy), y1 = min(y0 + 1, coarser.height - 1), fy = sy - Float(y0)
                            for x in 0..<width where weights[y * width + x] < 1 {
                                let sx = min(max((Float(x) + 0.5) / 2 - 0.5, 0), Float(coarser.width - 1))
                                let x0 = Int(sx), x1 = min(x0 + 1, coarser.width - 1), fx = sx - Float(x0)
                                let top = coarse[y0 * coarser.width + x0] * (1 - fx) + coarse[y0 * coarser.width + x1] * fx
                                let bottom = coarse[y1 * coarser.width + x0] * (1 - fx) + coarse[y1 * coarser.width + x1] * fx
                                let value = top * (1 - fy) + bottom * fy
                                let index = y * width + x
                                colors[index] = colors[index] * weights[index] + value * (1 - weights[index])
                                weights[index] = 1
                            }
                        }
                    }
                }
            }
        }
    }
}
