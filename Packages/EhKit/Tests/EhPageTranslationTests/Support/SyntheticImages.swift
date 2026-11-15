import CoreGraphics
import Foundation
import ImageIO

/// Images made by the tests, so no picture is a fixture.
enum SyntheticImages {
    static let sRGB = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

    /// An RGB image of the given size drawn by `draw` in a top-left-origin context.
    static func image(
        width: Int, height: Int, space: CGColorSpace = sRGB, alpha: Bool = false, draw: (CGContext) -> Void
    ) -> CGImage? {
        let info = alpha ? CGImageAlphaInfo.premultipliedLast : .noneSkipLast
        let bytesPerRow = space.model == .monochrome ? width : width * 4
        let bitmapInfo = space.model == .monochrome ? CGImageAlphaInfo.none.rawValue : info.rawValue
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: bytesPerRow,
            space: space, bitmapInfo: bitmapInfo
        ) else { return nil }
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        draw(context)
        return context.makeImage()
    }

    /// An image split into vertical bands of the given colours, left to right.
    static func bands(width: Int, height: Int, colors: [(CGFloat, CGFloat, CGFloat)]) -> CGImage? {
        image(width: width, height: height) { context in
            let band = CGFloat(width) / CGFloat(colors.count)
            for (index, color) in colors.enumerated() {
                context.setFillColor(red: color.0, green: color.1, blue: color.2, alpha: 1)
                context.fill(CGRect(x: band * CGFloat(index), y: 0, width: band, height: CGFloat(height)))
            }
        }
    }

    /// Something like a manga page: paper, panel borders, balloons with columns of "text", a
    /// gradient and screentone, and noise, so that a JPEG of it is about as hard to decode as a
    /// real page.
    static func page(width: Int, height: Int) -> CGImage? {
        image(width: width, height: height) { context in
            let w = CGFloat(width), h = CGFloat(height)
            context.setFillColor(gray: 1, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: w, height: h))
            let gradient = CGGradient(
                colorsSpace: sRGB, colors: [CGColor(gray: 0.85, alpha: 1), CGColor(gray: 0.25, alpha: 1)] as CFArray,
                locations: nil
            )
            if let gradient {
                context.saveGState()
                context.clip(to: CGRect(x: 0, y: h * 0.55, width: w, height: h * 0.45))
                context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: w, y: h), options: [])
                context.restoreGState()
            }
            context.setFillColor(gray: 0.1, alpha: 1)
            let dot = max(2, w / 300)
            for y in stride(from: h * 0.05, to: h * 0.5, by: dot * 3) {
                for x in stride(from: w * 0.55, to: w * 0.95, by: dot * 3) {
                    context.fillEllipse(in: CGRect(x: x, y: y, width: dot, height: dot))
                }
            }
            context.setStrokeColor(gray: 0, alpha: 1)
            context.setLineWidth(max(2, w / 250))
            context.stroke(CGRect(x: w * 0.03, y: h * 0.03, width: w * 0.94, height: h * 0.94))
            for index in 0..<6 {
                let balloon = CGRect(
                    x: w * (0.08 + 0.14 * CGFloat(index)), y: h * (0.1 + 0.07 * CGFloat(index % 3)),
                    width: w * 0.12, height: h * 0.25
                )
                context.setFillColor(gray: 1, alpha: 1)
                context.fillEllipse(in: balloon)
                context.strokeEllipse(in: balloon)
                context.setFillColor(gray: 0, alpha: 1)
                for column in 0..<3 {
                    context.fill(CGRect(
                        x: balloon.midX + (CGFloat(column) - 1.5) * balloon.width * 0.18,
                        y: balloon.minY + balloon.height * 0.2, width: balloon.width * 0.09,
                        height: balloon.height * 0.6
                    ))
                }
            }
            var generator = SplitMix(seed: 7)
            for _ in 0..<(width * height / 400) {
                let x = CGFloat(generator.next() % UInt64(width)), y = CGFloat(generator.next() % UInt64(height))
                context.setFillColor(gray: CGFloat(generator.next() % 256) / 255, alpha: 1)
                context.fill(CGRect(x: x, y: y, width: 2, height: 2))
            }
        }
    }

    /// `image` encoded as `type` (a UTI such as `public.jpeg`), with an EXIF orientation if given.
    static func encode(
        _ image: CGImage, as type: String, quality: Double = 0.9, orientation: Int? = nil
    ) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, type as CFString, 1, nil) else { return nil }
        var properties: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality]
        if let orientation { properties[kCGImagePropertyOrientation] = orientation }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    /// An animated GIF of `frames`.
    static func gif(_ frames: [CGImage]) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data, "com.compuserve.gif" as CFString, frames.count, nil
        ) else { return nil }
        let delay = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.1]] as CFDictionary
        for frame in frames { CGImageDestinationAddImage(destination, frame, delay) }
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}

/// A small deterministic random generator, so synthetic pages are the same on every run.
struct SplitMix {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
