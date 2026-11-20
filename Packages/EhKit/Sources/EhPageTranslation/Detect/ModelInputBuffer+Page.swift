import CoreGraphics
import Foundation

/// How a detector's input is made from the page.
enum InputResampling: Sendable {
    /// Core Graphics' high-quality resampling.
    case coreGraphics
    /// OpenCV's bilinear filter (`BilinearResize`).
    case openCVBilinear
}

extension ModelInputBuffer {
    /// Draws `region` of `page` into the buffer as `placement` asks, the rest grey (`padding`),
    /// and returns where it went.
    func render(
        _ page: PageBitmap, region: PixelRect, placement: Letterbox.Placement, padding: UInt8,
        resampling: InputResampling
    ) throws -> Letterbox {
        let letterbox = Letterbox(region: region, inputWidth: width, inputHeight: height, placement: placement)
        switch resampling {
        case .coreGraphics:
            guard let image = region == page.fullRect ? page.cgImage : page.crop(region) else {
                throw ModelInputBufferError.context
            }
            if placement == .stretched {
                try drawStretched(image)
            } else {
                try draw(image, in: letterbox.inputRect.cgRect, padding: padding)
            }
        case .openCVBilinear:
            try drawBilinear(page, region: region, at: letterbox.inputRect, padding: padding)
        }
        return letterbox
    }

    /// Fills the buffer with grey and resizes `region` of the page into `rect` with
    /// `BilinearResize`, straight from the page's red-first pixels into the buffer's blue-first
    /// ones.
    private func drawBilinear(_ page: PageBitmap, region: PixelRect, at rect: PixelRect, padding: UInt8) throws {
        try withMutableBytes { base, bytesPerRow in
            let bytes = base.assumingMemoryBound(to: UInt8.self)
            let grey = UInt32(padding)
            let pixel = UInt32(255) << 24 | grey << 16 | grey << 8 | grey
            for y in 0..<height {
                (base + y * bytesPerRow).assumingMemoryBound(to: UInt32.self).update(repeating: pixel, count: width)
            }
            guard !rect.isEmpty else { return }
            page.pixels.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
                guard let pixels = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
                BilinearResize.resize(
                    source: pixels + region.y0 * page.bytesPerRow + region.x0 * 4,
                    width: region.width, height: region.height, bytesPerRow: page.bytesPerRow,
                    into: bytes + rect.y0 * bytesPerRow + rect.x0 * 4,
                    width: rect.width, height: rect.height, bytesPerRow: bytesPerRow, swapsRedAndBlue: true
                )
            }
        }
    }
}

extension PageBitmap {
    /// The whole bitmap as a rectangle.
    public var fullRect: PixelRect { PixelRect(x: 0, y: 0, width: width, height: height) }
}
