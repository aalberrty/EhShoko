import CoreGraphics

/// One pixel's colour as the page stores it: values of the page's own colour space, never
/// converted.
struct PixelColor: Hashable, Sendable {
    var red: UInt8
    var green: UInt8
    var blue: UInt8

    static let white = PixelColor(red: 255, green: 255, blue: 255)
    static let black = PixelColor(red: 0, green: 0, blue: 0)

    /// Brightness, 0 to 255.
    @inline(__always)
    var luma: Int { (Int(red) * 77 + Int(green) * 150 + Int(blue) * 29) >> 8 }

    /// The largest difference of one channel.
    @inline(__always)
    func difference(_ other: PixelColor) -> Int {
        max(abs(Int(red) - Int(other.red)), abs(Int(green) - Int(other.green)), abs(Int(blue) - Int(other.blue)))
    }

    /// This colour in `space`, the page's, so that drawing with it writes these very values.
    func cgColor(in space: CGColorSpace) -> CGColor {
        let components = [CGFloat(red) / 255, CGFloat(green) / 255, CGFloat(blue) / 255, 1]
        return CGColor(colorSpace: space, components: components)
            ?? CGColor(red: components[0], green: components[1], blue: components[2], alpha: 1)
    }
}

/// Counts colours channel by channel, to take their median without sorting them.
struct ColorHistogram {
    private var red = [Int](repeating: 0, count: 256)
    private var green = [Int](repeating: 0, count: 256)
    private var blue = [Int](repeating: 0, count: 256)
    private(set) var count = 0

    mutating func add(_ color: PixelColor) {
        red[Int(color.red)] += 1
        green[Int(color.green)] += 1
        blue[Int(color.blue)] += 1
        count += 1
    }

    /// The median of each channel; `nil` when nothing was added.
    var median: PixelColor? {
        guard count > 0 else { return nil }
        return PixelColor(red: Self.median(red, count), green: Self.median(green, count), blue: Self.median(blue, count))
    }

    private static func median(_ bins: [Int], _ count: Int) -> UInt8 {
        var seen = 0
        for value in 0..<256 {
            seen += bins[value]
            if seen * 2 >= count { return UInt8(value) }
        }
        return 255
    }
}

/// Otsu's threshold: the value that best splits a histogram of 256 bins into two classes.
enum Otsu {
    static func threshold(_ histogram: [Int]) -> Int {
        let total = histogram.reduce(0, +)
        guard total > 0, histogram.count == 256 else { return 127 }
        var sum = 0.0
        for value in 0..<256 { sum += Double(value * histogram[value]) }
        var sumBelow = 0.0, below = 0, best = 0.0, threshold = 127
        for value in 0..<256 {
            below += histogram[value]
            if below == 0 { continue }
            let above = total - below
            if above == 0 { break }
            sumBelow += Double(value * histogram[value])
            let meanBelow = sumBelow / Double(below), meanAbove = (sum - sumBelow) / Double(above)
            let between = Double(below) * Double(above) * (meanBelow - meanAbove) * (meanBelow - meanAbove)
            if between > best {
                best = between
                threshold = value
            }
        }
        return threshold
    }
}
