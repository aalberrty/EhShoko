import Foundation

/// A copy of one rectangle of the page. Finding a balloon, measuring the lettering and erasing
/// all work on such a window, so their cost follows the size of the text and not of the page,
/// and the page itself is never written.
struct PixelWindow: Sendable {
    /// The rectangle in page pixels.
    let rect: PixelRect
    let pageWidth: Int
    let pageHeight: Int
    /// Red, green, blue and one unused byte for each pixel of `rect`, row by row.
    var rgba: [UInt8]

    var width: Int { rect.width }
    var height: Int { rect.height }
    var count: Int { rect.area }

    /// Copies `rect`, cut to the page, out of `page`.
    init(page: PageBitmap, rect: PixelRect) {
        let rect = rect.clamped(width: page.width, height: page.height)
        self.rect = rect
        pageWidth = page.width
        pageHeight = page.height
        let rowBytes = rect.width * 4
        var copy = [UInt8](repeating: 255, count: rect.area * 4)
        if !rect.isEmpty {
            page.pixels.withUnsafeBytes { source in
                copy.withUnsafeMutableBytes { destination in
                    guard let from = source.baseAddress, let to = destination.baseAddress else { return }
                    for row in 0..<rect.height {
                        let offset = (rect.y0 + row) * page.bytesPerRow + rect.x0 * 4
                        (to + row * rowBytes).copyMemory(from: from + offset, byteCount: rowBytes)
                    }
                }
            }
        }
        rgba = copy
    }

    /// The part of `window` inside `rect`.
    init(cropping window: PixelWindow, to rect: PixelRect) {
        let rect = rect.intersection(window.rect)
        self.rect = rect
        pageWidth = window.pageWidth
        pageHeight = window.pageHeight
        var copy = [UInt8](repeating: 255, count: rect.area * 4)
        for row in 0..<rect.height {
            let from = window.index(rect.x0, rect.y0 + row) * 4, to = row * rect.width * 4
            copy.replaceSubrange(to..<(to + rect.width * 4), with: window.rgba[from..<(from + rect.width * 4)])
        }
        rgba = copy
    }

    /// The part of `plane`, a plane the size of this window, inside `rect`.
    func crop(_ plane: [UInt8], to rect: PixelRect) -> [UInt8] {
        let rect = rect.intersection(self.rect)
        var out = [UInt8](repeating: 0, count: rect.area)
        for row in 0..<rect.height {
            let from = index(rect.x0, rect.y0 + row), to = row * rect.width
            out.replaceSubrange(to..<(to + rect.width), with: plane[from..<(from + rect.width)])
        }
        return out
    }

    /// The colour of the pixel at `index` of the window, row by row.
    @inline(__always)
    func color(_ index: Int) -> PixelColor {
        let offset = index * 4
        return PixelColor(red: rgba[offset], green: rgba[offset + 1], blue: rgba[offset + 2])
    }

    @inline(__always)
    mutating func set(_ index: Int, _ color: PixelColor) {
        let offset = index * 4
        rgba[offset] = color.red
        rgba[offset + 1] = color.green
        rgba[offset + 2] = color.blue
    }

    /// The window's index of the page pixel (`x`, `y`), which must lie in `rect`.
    @inline(__always)
    func index(_ x: Int, _ y: Int) -> Int { (y - rect.y0) * rect.width + x - rect.x0 }

    /// Whether the window's edge at this side is also the page's edge.
    func touchesPageEdge(left: Bool = false, top: Bool = false, right: Bool = false, bottom: Bool = false) -> Bool {
        (left && rect.x0 == 0) || (top && rect.y0 == 0) || (right && rect.x1 == pageWidth)
            || (bottom && rect.y1 == pageHeight)
    }

    /// `other`, a rectangle in page pixels, in the window's own coordinates and cut to it.
    func local(_ other: PixelRect) -> PixelRect {
        let cut = other.intersection(rect)
        guard !cut.isEmpty else { return .zero }
        return PixelRect(x0: cut.x0 - rect.x0, y0: cut.y0 - rect.y0, x1: cut.x1 - rect.x0, y1: cut.y1 - rect.y0)
    }

    /// Each pixel's brightness.
    func lumaPlane() -> [UInt8] {
        var plane = [UInt8](repeating: 0, count: count)
        rgba.withUnsafeBufferPointer { source in
            plane.withUnsafeMutableBufferPointer { destination in
                for index in 0..<destination.count {
                    let offset = index * 4
                    let luma = (Int(source[offset]) * 77 + Int(source[offset + 1]) * 150 + Int(source[offset + 2]) * 29) >> 8
                    destination[index] = UInt8(luma)
                }
            }
        }
        return plane
    }

    /// Each pixel's largest channel difference from `color`, at most 255.
    func differencePlane(from color: PixelColor) -> [UInt8] {
        var plane = [UInt8](repeating: 0, count: count)
        let red = Int(color.red), green = Int(color.green), blue = Int(color.blue)
        rgba.withUnsafeBufferPointer { source in
            plane.withUnsafeMutableBufferPointer { destination in
                for index in 0..<destination.count {
                    let offset = index * 4
                    let difference = max(
                        abs(Int(source[offset]) - red), abs(Int(source[offset + 1]) - green),
                        abs(Int(source[offset + 2]) - blue)
                    )
                    destination[index] = UInt8(difference)
                }
            }
        }
        return plane
    }
}

extension RegionMask {
    /// A plane the size of `window`, set where this mask is.
    func plane(in window: PixelWindow) -> [UInt8] {
        var plane = [UInt8](repeating: 0, count: window.count)
        let cut = rect.intersection(window.rect)
        guard !cut.isEmpty else { return plane }
        for y in cut.y0..<cut.y1 {
            let from = (y - rect.y0) * rect.width + cut.x0 - rect.x0, to = window.index(cut.x0, y)
            for x in 0..<cut.width where bits[from + x] != 0 { plane[to + x] = 1 }
        }
        return plane
    }

    /// The mask of a plane the size of `window`, cut to the smallest rectangle that holds its
    /// set pixels; `nil` when none is set.
    init?(plane: [UInt8], in window: PixelWindow) {
        let width = window.width, height = window.height
        var x0 = width, y0 = height, x1 = 0, y1 = 0
        plane.withUnsafeBufferPointer { bits in
            for y in 0..<height {
                let row = y * width
                for x in 0..<width where bits[row + x] != 0 {
                    if x < x0 { x0 = x }
                    if x >= x1 { x1 = x + 1 }
                    if y < y0 { y0 = y }
                    y1 = y + 1
                }
            }
        }
        guard x1 > x0, y1 > y0 else { return nil }
        var bits = [UInt8](repeating: 0, count: (x1 - x0) * (y1 - y0))
        for y in y0..<y1 {
            let from = y * width + x0, to = (y - y0) * (x1 - x0)
            for x in 0..<(x1 - x0) where plane[from + x] != 0 { bits[to + x] = 1 }
        }
        self.init(
            rect: PixelRect(x0: x0 + window.rect.x0, y0: y0 + window.rect.y0, x1: x1 + window.rect.x0, y1: y1 + window.rect.y0),
            bits: bits
        )
    }
}
