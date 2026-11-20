import CoreML
import Foundation

/// Raw-bit access to the float16 `MLMultiArray`s the translator feeds and reads. Swift's
/// `Float16` does not exist on Intel Macs, so values are `UInt16` bits (`Half`).
extension MLMultiArray {
    static func half(_ shape: [Int]) throws -> MLMultiArray {
        try MLMultiArray(shape: shape.map { NSNumber(value: $0) }, dataType: .float16)
    }

    var intShape: [Int] { shape.map(\.intValue) }

    /// Calls `body` with the array's halves and its strides, in elements.
    @discardableResult
    func withMutableHalves<R>(_ body: (UnsafeMutablePointer<UInt16>, [Int]) throws -> R) rethrows -> R? {
        try withUnsafeMutableBytes { raw, strides in
            guard let base = raw.baseAddress else { return nil }
            return try body(base.assumingMemoryBound(to: UInt16.self), strides)
        }
    }

    @discardableResult
    func withHalves<R>(_ body: (UnsafePointer<UInt16>, [Int]) throws -> R) rethrows -> R? {
        let strides = self.strides.map(\.intValue)
        return try withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return nil }
            return try body(base.assumingMemoryBound(to: UInt16.self), strides)
        }
    }

    /// Sets every element to zero bits.
    func zero() {
        withUnsafeMutableBytes { raw, _ in
            if let base = raw.baseAddress { memset(base, 0, raw.count) }
        }
    }

    /// Sets element `i` of the last axis to `value(i)`, for an array whose other axes are 1.
    func fillLastAxis(_ value: (Int) -> UInt16) {
        let count = shape.last?.intValue ?? 0
        withMutableHalves { pointer, strides in
            let stride = strides[strides.count - 1]
            for index in 0..<count { pointer[index * stride] = value(index) }
        }
    }
}
