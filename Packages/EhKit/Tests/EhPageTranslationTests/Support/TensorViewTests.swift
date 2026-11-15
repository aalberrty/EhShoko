import CoreML
@testable import EhPageTranslation
import Testing

@Suite struct TensorViewTests {
    /// A multi-array with explicit strides; every element outside the shape (the padding)
    /// holds -999, so a read that ignores the strides shows.
    private func tensor(
        shape: [Int], strides: [Int], half: Bool, value: ([Int]) -> Float
    ) throws -> MLMultiArray {
        let size = half ? 2 : 4
        let count = strides[0] * shape[0]
        let pointer = UnsafeMutableRawPointer.allocate(byteCount: count * size, alignment: 16)
        func store(_ v: Float, at offset: Int) {
            if half {
                pointer.storeBytes(of: Half.fromFloat(v), toByteOffset: offset * 2, as: UInt16.self)
            } else {
                pointer.storeBytes(of: v, toByteOffset: offset * 4, as: Float.self)
            }
        }
        for offset in 0..<count { store(-999, at: offset) }
        var index = [Int](repeating: 0, count: shape.count)
        while true {
            store(value(index), at: zip(index, strides).reduce(0) { $0 + $1.0 * $1.1 })
            var axis = shape.count - 1
            while axis >= 0 {
                index[axis] += 1
                if index[axis] < shape[axis] { break }
                index[axis] = 0
                axis -= 1
            }
            if axis < 0 { break }
        }
        return try MLMultiArray(
            dataPointer: pointer, shape: shape.map { NSNumber(value: $0) }, dataType: half ? .float16 : .float32,
            strides: strides.map { NSNumber(value: $0) }, deallocator: { $0.deallocate() }
        )
    }

    private func row(_ view: TensorView, _ channel: Int) -> [Float] {
        var values = [Float](repeating: 0, count: view.positions)
        values.withUnsafeMutableBufferPointer { buffer in
            if let base = buffer.baseAddress { view.copyRow(channel, into: base) }
        }
        return values
    }

    @Test(arguments: [false, true])
    func rankThreeWithPaddedChannels(half: Bool) throws {
        let array = try tensor(shape: [1, 2, 3], strides: [16, 8, 1], half: half) { Float($0[1] * 10 + $0[2]) }
        try array.withTensorView { view in
            #expect(view.positions == 3)
            #expect(view.at(0, 2) == 2)
            #expect(view.at(1, 0) == 10)
            #expect(row(view, 1) == [10, 11, 12])
        }
    }

    @Test func rankThreeWithStridedPositions() throws {
        let array = try tensor(shape: [1, 2, 3], strides: [12, 6, 2], half: false) { Float($0[1] * 10 + $0[2]) }
        try array.withTensorView { view in
            #expect(row(view, 0) == [0, 1, 2])
            #expect(row(view, 1) == [10, 11, 12])
        }
    }

    @Test(arguments: [false, true])
    func rankFourReadRowByRow(half: Bool) throws {
        // Rows of 3 padded to 4, as the Neural Engine lays out a long axis.
        let value: ([Int]) -> Float = { Float($0[1] * 100 + $0[2] * 10 + $0[3]) }
        let padded = try tensor(shape: [1, 2, 2, 3], strides: [32, 16, 4, 1], half: half, value: value)
        let packed = try tensor(shape: [1, 2, 2, 3], strides: [12, 6, 3, 1], half: half, value: value)
        for array in [padded, packed] {
            try array.withTensorView { view in
                #expect(view.positions == 6)
                #expect(view.at(1, 4) == 111)
                #expect(view.at(1, 1, 2) == 112)
                #expect(row(view, 1) == [100, 101, 102, 110, 111, 112])
                #expect(row(view, 0) == [0, 1, 2, 10, 11, 12])
            }
        }
    }

    @Test func rejectsIntegerOutputs() throws {
        let array = try MLMultiArray(shape: [1, 2, 2], dataType: .int32)
        #expect(throws: TensorViewError.unsupportedDataType(MLMultiArrayDataType.int32.rawValue)) {
            try array.withTensorView { _ in }
        }
    }
}
