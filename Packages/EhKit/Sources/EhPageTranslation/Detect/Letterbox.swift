import CoreGraphics

/// Where a part of the page lands in a model's input, and the way back: stretched over the
/// whole input (the DETR-style detectors and the readers), or scaled to fit with its shape kept
/// and the rest padded, at the top left (RTMDet) or centred (Ultralytics YOLO).
struct Letterbox: Sendable, Equatable {
    enum Placement: Sendable {
        case stretched
        case topLeft
        case centred
    }

    /// The part of the page, in page-bitmap pixels.
    let region: PixelRect
    let inputWidth: Int
    let inputHeight: Int
    /// Input pixels for each page pixel.
    let scaleX: Double
    let scaleY: Double
    /// Where the region's top left lands in the input.
    let offsetX: Int
    let offsetY: Int
    /// The region's size in the input.
    let scaledWidth: Int
    let scaledHeight: Int

    init(region: PixelRect, inputWidth: Int, inputHeight: Int, placement: Placement) {
        self.region = region
        self.inputWidth = inputWidth
        self.inputHeight = inputHeight
        let width = Double(max(region.width, 1)), height = Double(max(region.height, 1))
        switch placement {
        case .stretched:
            scaleX = Double(inputWidth) / width
            scaleY = Double(inputHeight) / height
            scaledWidth = inputWidth
            scaledHeight = inputHeight
            offsetX = 0
            offsetY = 0
        case .topLeft, .centred:
            let scale = min(Double(inputWidth) / width, Double(inputHeight) / height)
            scaleX = scale
            scaleY = scale
            // Python's round(), half to even, as the research's references were made.
            scaledWidth = min(inputWidth, Int((width * scale).rounded(.toNearestOrEven)))
            scaledHeight = min(inputHeight, Int((height * scale).rounded(.toNearestOrEven)))
            offsetX = placement == .centred ? (inputWidth - scaledWidth) / 2 : 0
            offsetY = placement == .centred ? (inputHeight - scaledHeight) / 2 : 0
        }
    }

    /// Where the region is drawn in the input.
    var inputRect: PixelRect {
        PixelRect(x: offsetX, y: offsetY, width: scaledWidth, height: scaledHeight)
    }

    /// A rectangle in input pixels as page pixels, cut to the region; `.zero` when nothing of it
    /// is in the region or it is not finite.
    func pageRect(fromInput rect: CGRect) -> CGRect {
        let page = CGRect(
            x: Double(region.x0) + (rect.minX - Double(offsetX)) / scaleX,
            y: Double(region.y0) + (rect.minY - Double(offsetY)) / scaleY,
            width: rect.width / scaleX, height: rect.height / scaleY
        )
        guard [page.origin.x, page.origin.y, page.size.width, page.size.height].allSatisfy(\.isFinite) else { return .zero }
        let clipped = page.intersection(region.cgRect)
        return clipped.isNull ? .zero : clipped
    }

    /// The input position (continuous, in input pixels) of the centre of page pixel column `x`.
    @inline(__always)
    func inputX(ofPixel x: Int) -> Double {
        (Double(x - region.x0) + 0.5) * scaleX + Double(offsetX)
    }

    /// The input position of the centre of page pixel row `y`.
    @inline(__always)
    func inputY(ofPixel y: Int) -> Double {
        (Double(y - region.y0) + 0.5) * scaleY + Double(offsetY)
    }
}
