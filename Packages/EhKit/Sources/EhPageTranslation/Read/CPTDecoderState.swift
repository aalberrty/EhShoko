import CoreML

/// The shapes of the CPT decoder's inputs, read from its description: a cache of `length`
/// positions, each holding `layers` × `heads` keys and values of `width` numbers.
struct CPTCacheShape: Sendable, Equatable {
    var layers: Int
    var heads: Int
    var length: Int
    var width: Int
    var cacheType: MLMultiArrayDataType
    var maskType: MLMultiArrayDataType
    var tokenShape: [Int]
    var tokenType: MLMultiArrayDataType
    var positionShape: [Int]
    var positionType: MLMultiArrayDataType

    init(layers: Int, heads: Int, length: Int, width: Int, cacheType: MLMultiArrayDataType = .float32) {
        self.layers = layers
        self.heads = heads
        self.length = length
        self.width = width
        self.cacheType = cacheType
        maskType = cacheType
        tokenShape = [1, 1]
        tokenType = .int32
        positionShape = [1]
        positionType = .int32
    }

    init(_ decoder: CoreMLModel) throws(ModelSignatureError) {
        let keys = try decoder.inputArray("kcache", rank: 4)
        let values = try decoder.inputArray("vcache", rank: 4)
        guard values.shape == keys.shape, values.type == keys.type else { throw .unexpectedShape("vcache", values.shape) }
        let mask = try decoder.inputArray("mask", rank: 2)
        guard mask.shape == [1, keys.shape[2]] else { throw .unexpectedShape("mask", mask.shape) }
        guard case let .multiArray(tokenShape, tokenType) = decoder.inputs["token"] else { throw .missingInput("token") }
        guard case let .multiArray(positionShape, positionType) = decoder.inputs["pos"] else { throw .missingInput("pos") }
        for name in ["cross_k", "cross_v"] where decoder.inputs[name] == nil { throw .missingInput(name) }
        _ = try decoder.outputShape("k_new", rank: 4)
        _ = try decoder.outputShape("v_new", rank: 4)
        guard decoder.outputs["next"] != nil else { throw .missingOutput("next") }
        for type in [keys.type, mask.type] where type != .float16 && type != .float32 { throw .unexpectedType("kcache") }
        layers = keys.shape[0]
        heads = keys.shape[1]
        length = keys.shape[2]
        width = keys.shape[3]
        cacheType = keys.type
        maskType = mask.type
        self.tokenShape = tokenShape
        self.tokenType = tokenType
        self.positionShape = positionShape
        self.positionType = positionType
    }
}

/// The decoder's inputs for one crop, changed in place from step to step: the token and its
/// position, the mask that opens the cache one position a step, and the cache itself.
///
/// Not `Sendable`: it lives in one read, and each step changes it only after the last
/// prediction that read it has returned.
final class CPTDecoderState {
    static let closed: Float = -1e4

    let shape: CPTCacheShape
    let token: MLMultiArray
    let position: MLMultiArray
    let mask: MLMultiArray
    let keys: MLMultiArray
    let values: MLMultiArray
    let inputs: MLDictionaryFeatureProvider

    init(_ shape: CPTCacheShape, crossKeys: MLMultiArray, crossValues: MLMultiArray) throws {
        self.shape = shape
        func array(_ dimensions: [Int], _ type: MLMultiArrayDataType) throws -> MLMultiArray {
            try MLMultiArray(shape: dimensions.map { NSNumber(value: $0) }, dataType: type)
        }
        let cache = [shape.layers, shape.heads, shape.length, shape.width]
        token = try array(shape.tokenShape, shape.tokenType)
        position = try array(shape.positionShape, shape.positionType)
        mask = try array([1, shape.length], shape.maskType)
        keys = try array(cache, shape.cacheType)
        values = try array(cache, shape.cacheType)
        // A new array's memory is not cleared, and a closed position still enters attention with
        // a weight of zero: zero times a stale NaN or infinity (likely in half precision) is NaN.
        for array in [keys, values] {
            array.withUnsafeMutableBytes { raw, _ in _ = raw.initializeMemory(as: UInt8.self, repeating: 0) }
        }
        Self.fill(mask, with: Self.closed)
        inputs = try MLDictionaryFeatureProvider(dictionary: [
            "token": token, "pos": position, "mask": mask, "kcache": keys, "vcache": values,
            "cross_k": crossKeys, "cross_v": crossValues
        ])
    }

    /// Sets the inputs for the step at `position`, which feeds `token`: the positions before it
    /// are open.
    func prepare(token value: Int, position step: Int) throws {
        Self.setInteger(token, value)
        Self.setInteger(position, step)
        if step > 0 { Self.set(mask, at: step - 1, to: 0) }
    }

    /// Copies one step's keys and values, (layers, heads, 1, width) with any strides, into
    /// position `step` of the cache.
    func store(keys newKeys: MLMultiArray, values newValues: MLMultiArray, at step: Int) throws {
        try Self.copy(newKeys, into: keys, at: step)
        try Self.copy(newValues, into: values, at: step)
    }

    // MARK: Array access

    static func copy(_ source: MLMultiArray, into cache: MLMultiArray, at step: Int) throws {
        let sourceShape = source.shape.map(\.intValue), cacheShape = cache.shape.map(\.intValue)
        guard sourceShape.count == 4, cacheShape.count == 4, sourceShape[0] == cacheShape[0], sourceShape[1] == cacheShape[1],
              sourceShape[2] >= 1, sourceShape[3] == cacheShape[3], step >= 0, step < cacheShape[2]
        else { throw ModelSignatureError.unexpectedShape("k_new", sourceShape) }
        let layers = sourceShape[0], heads = sourceShape[1], width = sourceShape[3]
        let sourceStrides = source.strides.map(\.intValue)
        let sourceIsHalf = source.dataType == .float16, cacheIsHalf = cache.dataType == .float16
        guard sourceIsHalf || source.dataType == .float32 else { throw ModelSignatureError.unexpectedType("k_new") }
        source.withUnsafeBytes { from in
            cache.withUnsafeMutableBytes { to, cacheStrides in
                guard let from = from.baseAddress, let to = to.baseAddress else { return }
                for layer in 0..<layers {
                    for head in 0..<heads {
                        let sourceBase = layer * sourceStrides[0] + head * sourceStrides[1]
                        let cacheBase = layer * cacheStrides[0] + head * cacheStrides[1] + step * cacheStrides[2]
                        if sourceIsHalf == cacheIsHalf, sourceStrides[3] == 1, cacheStrides[3] == 1 {
                            let size = sourceIsHalf ? 2 : 4
                            (to + cacheBase * size).copyMemory(from: from + sourceBase * size, byteCount: width * size)
                            continue
                        }
                        for k in 0..<width {
                            let s = sourceBase + k * sourceStrides[3], c = cacheBase + k * cacheStrides[3]
                            let value = sourceIsHalf
                                ? Half.toFloat(from.load(fromByteOffset: s * 2, as: UInt16.self))
                                : from.load(fromByteOffset: s * 4, as: Float.self)
                            if cacheIsHalf {
                                to.storeBytes(of: Half.fromFloat(value), toByteOffset: c * 2, as: UInt16.self)
                            } else {
                                to.storeBytes(of: value, toByteOffset: c * 4, as: Float.self)
                            }
                        }
                    }
                }
            }
        }
    }

    static func fill(_ array: MLMultiArray, with value: Float) {
        for index in 0..<array.count { set(array, at: index, to: value) }
    }

    /// Element `index` of a one-row floating-point array (the mask).
    static func set(_ array: MLMultiArray, at index: Int, to value: Float) {
        array.withUnsafeMutableBytes { raw, strides in
            let offset = index * (strides.last ?? 1)
            if array.dataType == .float16 {
                raw.storeBytes(of: Half.fromFloat(value), toByteOffset: offset * 2, as: UInt16.self)
            } else {
                raw.storeBytes(of: value, toByteOffset: offset * 4, as: Float.self)
            }
        }
    }

    /// The single element of a token or position array.
    static func setInteger(_ array: MLMultiArray, _ value: Int) {
        if array.dataType == .int32 {
            array.withUnsafeMutableBytes { raw, _ in raw.storeBytes(of: Int32(value), as: Int32.self) }
        } else {
            array[0] = NSNumber(value: value)
        }
    }
}
