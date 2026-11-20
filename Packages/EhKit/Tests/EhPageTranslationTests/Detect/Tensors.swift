import CoreML
@testable import EhPageTranslation
import Foundation

/// Model outputs made by hand, so a decoder can be tested without a model.
enum Tensors {
    /// A contiguous array of `shape` holding `values` (row-major), as float32 or float16.
    static func make(_ shape: [Int], half: Bool = false, values: [Float]) throws -> MLMultiArray {
        precondition(values.count == shape.reduce(1, *), "one value for each element")
        let array = try MLMultiArray(shape: shape.map { NSNumber(value: $0) }, dataType: half ? .float16 : .float32)
        array.withUnsafeMutableBytes { raw, _ in
            for (index, value) in values.enumerated() {
                if half {
                    raw.storeBytes(of: Half.fromFloat(value), toByteOffset: index * 2, as: UInt16.self)
                } else {
                    raw.storeBytes(of: value, toByteOffset: index * 4, as: Float.self)
                }
            }
        }
        return array
    }

    /// An array of `shape` whose last axis is padded to `rowLength` elements, as the Neural
    /// Engine lays some outputs out. `values` is row-major over `shape` without the padding.
    static func padded(_ shape: [Int], rowLength: Int, half: Bool = false, values: [Float]) throws -> MLMultiArray {
        precondition(values.count == shape.reduce(1, *) && rowLength >= shape[shape.count - 1])
        var strides = [Int](repeating: 1, count: shape.count)
        if shape.count > 1 { strides[shape.count - 2] = rowLength }
        for axis in stride(from: shape.count - 3, through: 0, by: -1) { strides[axis] = strides[axis + 1] * shape[axis + 1] }
        let size = half ? 2 : 4
        let capacity = strides[0] * shape[0]
        let pointer = UnsafeMutableRawPointer.allocate(byteCount: capacity * size, alignment: 16)
        pointer.initializeMemory(as: UInt8.self, repeating: 0xEE, count: capacity * size)
        for (index, value) in values.enumerated() {
            var rest = index, offset = 0
            for axis in stride(from: shape.count - 1, through: 0, by: -1) {
                offset += (rest % shape[axis]) * strides[axis]
                rest /= shape[axis]
            }
            if half {
                pointer.storeBytes(of: Half.fromFloat(value), toByteOffset: offset * 2, as: UInt16.self)
            } else {
                pointer.storeBytes(of: value, toByteOffset: offset * 4, as: Float.self)
            }
        }
        return try MLMultiArray(
            dataPointer: pointer, shape: shape.map { NSNumber(value: $0) }, dataType: half ? .float16 : .float32,
            strides: strides.map { NSNumber(value: $0) }, deallocator: { $0.deallocate() }
        )
    }

    static func zeros(_ shape: [Int], half: Bool = false) throws -> MLMultiArray {
        try make(shape, half: half, values: [Float](repeating: 0, count: shape.reduce(1, *)))
    }

    /// The outputs of a model run, by name.
    static func outputs(_ arrays: [String: MLMultiArray]) throws -> MLDictionaryFeatureProvider {
        try MLDictionaryFeatureProvider(dictionary: arrays.mapValues { MLFeatureValue(multiArray: $0) })
    }

    /// The logit whose sigmoid is `probability`.
    static func logit(_ probability: Float) -> Float {
        log(probability / (1 - probability))
    }
}
