import Accelerate
import CoreML

/// A read-only view of a model output of rank 3 or more holding `Float16` or `Float32`
/// values, honouring its strides: outputs from the Neural Engine can be padded. Valid only
/// inside `MLMultiArray.withTensorView(_:)`.
public struct TensorView {
    let base: UnsafeRawPointer
    let isHalf: Bool
    public let shape: [Int]
    public let strides: [Int]

    init(base: UnsafeRawPointer, isHalf: Bool, shape: [Int], strides: [Int]) {
        self.base = base
        self.isHalf = isHalf
        self.shape = shape
        self.strides = strides
    }

    /// The element at linear offset `i` (in elements, strides already applied).
    @inline(__always)
    public func value(_ i: Int) -> Float {
        isHalf
            ? Half.toFloat(base.load(fromByteOffset: i * 2, as: UInt16.self))
            : base.load(fromByteOffset: i * 4, as: Float.self)
    }

    /// The number of positions in a channel: N of a (1, C, N) tensor, H·W of a (1, C, H, W)
    /// one.
    public var positions: Int { shape.count == 4 ? shape[2] * shape[3] : shape[2] }

    /// The value at (channel `c`, position `n`) of a (1, C, N) tensor, or of a (1, C, H, W)
    /// tensor read row by row as N = H·W (the Neural Engine variants lay a long axis out in
    /// rows of 128).
    @inline(__always)
    public func at(_ c: Int, _ n: Int) -> Float {
        if shape.count == 4 {
            let w = shape[3]
            return value(c * strides[1] + (n / w) * strides[2] + (n % w) * strides[3])
        }
        return value(c * strides[1] + n * strides[2])
    }

    /// The value at (`c`, `y`, `x`) of a (1, C, H, W) tensor.
    @inline(__always)
    public func at(_ c: Int, _ y: Int, _ x: Int) -> Float {
        value(c * strides[1] + y * strides[2] + x * strides[3])
    }

    /// Copies channel `c` (`positions` values, read as `at(_:_:)` reads them) into `dst`.
    public func copyRow(_ c: Int, into dst: UnsafeMutablePointer<Float>) {
        let n = positions, offset = c * strides[1]
        // Contiguous when the channel's positions are not padded.
        let contiguous = shape.count == 4 ? (strides[3] == 1 && strides[2] == shape[3]) : strides[2] == 1
        guard contiguous else {
            for i in 0..<n { dst[i] = at(c, i) }
            return
        }
        if isHalf {
            Half.widen(base + offset * 2, dst, count: n)
        } else {
            dst.update(from: (base + offset * 4).assumingMemoryBound(to: Float.self), count: n)
        }
    }
}

public enum TensorViewError: Error, Equatable {
    /// The output holds integers or doubles, which no model of this pipeline returns.
    case unsupportedDataType(Int)
    case empty
}

extension MLMultiArray {
    /// Calls `body` with a view of this array's values. Throws for an array that is empty or
    /// holds anything but `Float16` or `Float32`, which a wrong model file would give.
    public func withTensorView<R>(_ body: (TensorView) throws -> R) throws -> R {
        let isHalf = dataType == .float16
        guard isHalf || dataType == .float32 else {
            throw TensorViewError.unsupportedDataType(dataType.rawValue)
        }
        let shape = self.shape.map(\.intValue), strides = self.strides.map(\.intValue)
        return try withUnsafeBytes { raw in
            guard let base = raw.baseAddress, count > 0 else { throw TensorViewError.empty }
            return try body(TensorView(base: base, isHalf: isHalf, shape: shape, strides: strides))
        }
    }
}
