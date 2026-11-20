import CoreGraphics
import CoreText
import Foundation

/// A typeface that can be brought to a stroke weight: by its `wght` axis when it has one, and
/// by stroking the glyph outlines ("faux bold") for what the face itself cannot reach.
struct FontFace: @unchecked Sendable {
    // `@unchecked Sendable` is safe here: `CTFontDescriptor` is an immutable Core Foundation
    // object that Core Text allows to be shared between threads, and every other property is
    // a value.
    let name: String
    let descriptor: CTFontDescriptor
    /// The range of the weight axis, for a variable face.
    let axis: ClosedRange<Double>?
    /// The stroke thickness, as a share of the size, the face has at sample values of its
    /// axis (one sample at 0 for a face without an axis), lightest first.
    let calibration: [(value: Double, weight: Double)]

    init(name: String, descriptor: CTFontDescriptor) {
        self.name = name
        self.descriptor = descriptor
        let font = CTFontCreateWithFontDescriptor(descriptor, 100, nil)
        var axis: ClosedRange<Double>?
        for entry in (CTFontCopyVariationAxes(font) as? [[CFString: Any]]) ?? [] {
            guard (entry[kCTFontVariationAxisIdentifierKey] as? NSNumber)?.uint32Value == Self.weightTag else { continue }
            let low = (entry[kCTFontVariationAxisMinimumValueKey] as? NSNumber)?.doubleValue ?? 100
            let high = (entry[kCTFontVariationAxisMaximumValueKey] as? NSNumber)?.doubleValue ?? 900
            if high > low { axis = low...high }
        }
        self.axis = axis
        if let axis {
            let step = (axis.upperBound - axis.lowerBound) / 6
            calibration = (0...6).map { index in
                let value = axis.lowerBound + step * Double(index)
                return (value, Self.strokeRatio(Self.font(descriptor, size: 100, axisValue: value)))
            }
        } else {
            calibration = [(0, Self.strokeRatio(font))]
        }
    }

    /// The tag of the weight axis, `wght`.
    static let weightTag: UInt32 = 0x7767_6874

    private static func font(_ descriptor: CTFontDescriptor, size: Double, axisValue: Double?) -> CTFont {
        let base = CTFontCreateWithFontDescriptor(descriptor, size, nil)
        guard let axisValue else { return base }
        let variation = [kCTFontVariationAttribute: [NSNumber(value: weightTag): NSNumber(value: axisValue)]]
        return CTFontCreateCopyWithAttributes(
            base, size, nil, CTFontDescriptorCreateWithAttributes(variation as CFDictionary)
        )
    }

    /// The font of `size` whose strokes come closest to `weight` (stroke thickness over
    /// size), and the stroke, in pixels, still missing from it.
    func matching(weight: Double, size: Double) -> (font: CTFont, extraStroke: Double) {
        guard let axis, let lightest = calibration.first, let heaviest = calibration.last else {
            let reached = calibration.first?.weight ?? weight
            let extra = max(0, (weight - reached) * size)
            // A hair of extra stroke only blurs a face that is close enough.
            return (Self.font(descriptor, size: size, axisValue: nil), extra > size * 0.012 ? extra : 0)
        }
        var value = lightest.value
        if weight >= heaviest.weight {
            value = heaviest.value
        } else if weight > lightest.weight {
            for (low, high) in zip(calibration, calibration.dropFirst()) where weight >= low.weight && weight <= high.weight {
                value = low.value + (high.value - low.value) * (weight - low.weight) / max(1e-6, high.weight - low.weight)
            }
        }
        let clamped = min(max(value, axis.lowerBound), axis.upperBound)
        let extra = max(0, (weight - min(weight, heaviest.weight)) * size)
        return (Self.font(descriptor, size: size, axisValue: clamped), extra)
    }

    /// The stroke thickness of sample characters over their size, measured as it is on a page.
    static func strokeRatio(_ font: CTFont) -> Double {
        let width = 560, height = 140
        var pixels = [UInt8](repeating: 255, count: width * height)
        pixels.withUnsafeMutableBytes { raw in
            guard let context = CGContext(
                data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return }
            let text = NSAttributedString(
                string: "国说永话", attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font]
            )
            context.setFillColor(gray: 0, alpha: 1)
            context.textPosition = CGPoint(x: 10, y: 30)
            CTLineDraw(CTLineCreateWithAttributedString(text), context)
        }
        let ink = pixels.map { $0 < 128 ? UInt8(1) : 0 }
        let strokes = StyleEstimator.strokeSamples(ink, width: width, height: height)
        return (StyleEstimator.median(strokes) ?? 8) / Double(CTFontGetSize(font))
    }
}

/// The faces a page is lettered in, one for each kind of lettering.
public struct FontLibrary: Sendable {
    let dialogue: FontFace
    let serif: FontFace
    let handwritten: FontFace

    func face(_ kind: LetteringFace) -> FontFace {
        switch kind {
        case .dialogue, .bold: dialogue
        case .serif: serif
        case .handwritten: handwritten
        }
    }

    /// The three subset fonts this target carries. Made once, on first use: measuring the
    /// faces' weights draws a few sample lines.
    public static let bundled = FontLibrary(
        dialogue: bundledFace(.dialogue), serif: bundledFace(.serif), handwritten: bundledFace(.handwritten)
    )

    /// The files of the bundled faces and the system face that stands in if one cannot be read.
    enum BundledFont: String, CaseIterable {
        case dialogue = "NotoSansSC-VF-GB2312"
        case serif = "NotoSerifSC-VF-GB2312"
        case handwritten = "EhShokoKai-Regular"

        var fallback: String {
            switch self {
            case .dialogue: "PingFangSC-Regular"
            case .serif: "STSongti-SC-Regular"
            case .handwritten: "STKaitiSC-Regular"
            }
        }

        var url: URL? {
            Bundle.module.url(forResource: rawValue, withExtension: "ttf", subdirectory: "Fonts")
        }
    }

    /// The descriptor of a bundled font, read from its file without registering it with the
    /// system; `nil` when the file is missing or is no font.
    static func bundledDescriptor(_ font: BundledFont) -> CTFontDescriptor? {
        guard let url = font.url,
              let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor]
        else { return nil }
        return descriptors.first
    }

    private static func bundledFace(_ font: BundledFont) -> FontFace {
        if let descriptor = bundledDescriptor(font) {
            return FontFace(name: font.rawValue, descriptor: descriptor)
        }
        return FontFace(name: font.fallback, descriptor: CTFontDescriptorCreateWithNameAndSize(font.fallback as CFString, 0))
    }
}
