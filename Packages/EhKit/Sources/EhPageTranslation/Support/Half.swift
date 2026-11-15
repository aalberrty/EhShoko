import Accelerate
import Foundation

/// IEEE half-precision helpers on raw `UInt16` bits.
///
/// Swift's `Float16` does not exist on Intel Macs, and this code runs on the Mac host as well
/// as on the phone, so the conversions are done on the bits. Both directions give exactly
/// what numpy and Core ML give.
public enum Half {
    /// Exact widening: every half value is a float value.
    @inline(__always)
    public static func toFloat(_ h: UInt16) -> Float {
        let sign = UInt32(h & 0x8000) << 16
        let exp = Int((h >> 10) & 0x1F)
        let mant = UInt32(h & 0x3FF)
        if exp == 0 {
            if mant == 0 { return Float(bitPattern: sign) }
            // Subnormal: mant * 2^-24.
            let v = Float(mant) * Float(bitPattern: 0x3380_0000)
            return sign == 0 ? v : -v
        }
        if exp == 31 { return Float(bitPattern: sign | 0x7F80_0000 | (mant << 13)) }
        return Float(bitPattern: sign | UInt32(exp - 15 + 127) << 23 | (mant << 13))
    }

    /// Float to half with round-to-nearest-even, as numpy's `astype(float16)` and Core ML's
    /// input conversion do. Handles subnormals, overflow to infinity and NaN.
    @inline(__always)
    public static func fromFloat(_ f: Float) -> UInt16 {
        let bits = f.bitPattern
        let sign = UInt16((bits >> 16) & 0x8000)
        let exp = Int((bits >> 23) & 0xFF)
        var mant = bits & 0x7F_FFFF
        if exp == 0xFF {
            return sign | 0x7C00 | (mant != 0 ? 0x200 : 0)
        }
        let e = exp - 127 + 15
        if e >= 31 { return sign | 0x7C00 }
        if e <= 0 {
            // The result is subnormal or zero: shift the whole significand into place and
            // round to nearest even.
            if e < -10 { return sign }
            mant |= 0x80_0000
            let shift = UInt32(14 - e)
            let half = mant >> shift
            let rem = mant & ((1 << shift) - 1)
            let mid = UInt32(1) << (shift - 1)
            var r = half
            if rem > mid || (rem == mid && (half & 1) == 1) { r += 1 }
            return sign | UInt16(r)
        }
        var h = UInt32(e) << 10 | (mant >> 13)
        let rem = mant & 0x1FFF
        // May carry into the exponent, which is still the right result.
        if rem > 0x1000 || (rem == 0x1000 && (h & 1) == 1) { h += 1 }
        return sign | UInt16(h)
    }

    /// Exact widening of `count` contiguous halves at `src` into `dst`.
    public static func widen(_ src: UnsafeRawPointer, _ dst: UnsafeMutablePointer<Float>, count: Int) {
        guard count > 0 else { return }
        var source = vImage_Buffer(
            data: UnsafeMutableRawPointer(mutating: src), height: 1, width: vImagePixelCount(count),
            rowBytes: count * 2
        )
        var destination = vImage_Buffer(
            data: dst, height: 1, width: vImagePixelCount(count), rowBytes: count * 4
        )
        vImageConvert_Planar16FtoPlanarF(&source, &destination, vImage_Flags(kvImageNoFlags))
    }
}
