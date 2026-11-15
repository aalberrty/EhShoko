import Accelerate

extension RTMDetDecoder {
    /// Balloon masks: each anchor's dynamic convolution (10 → 8 → 8 → 1, ReLU between) over the
    /// stride-8 mask features with the cell's position relative to the anchor, set where the
    /// logit is 0 or more, within 8 input pixels of the box. Only the cells a mask reads are
    /// computed.
    func masks(kernels: TensorView, features: TensorView, letterbox: Letterbox) -> MaskSampler {
        let side = features.shape[3], channels = features.shape[1]
        let featureStride = Float(inputSize) / Float(side)
        let priors = self.priors
        return MaskSampler(letterbox: letterbox, gridSide: side, threshold: 0, inclusive: true, margin: 8) {
            detection, window in
            guard channels == 8, detection.anchor < priors.count else { return [] }
            let count = window.width * window.height
            var parameters = [Float](repeating: 0, count: Self.maskParameterCount)
            for index in 0..<Self.maskParameterCount { parameters[index] = kernels.at(index, detection.anchor) }
            let prior = priors[detection.anchor]
            // The first layer's input: x and y relative to the anchor, then the 8 feature channels.
            var input = [Float](repeating: 0, count: 10 * count)
            for y in 0..<window.height {
                let cellY = window.y0 + y
                let relativeY = (prior.y - Float(cellY) * featureStride) / (prior.z * 8)
                for x in 0..<window.width {
                    let cellX = window.x0 + x, cell = y * window.width + x
                    input[cell] = (prior.x - Float(cellX) * featureStride) / (prior.z * 8)
                    input[count + cell] = relativeY
                    for channel in 0..<8 {
                        input[(2 + channel) * count + cell] = features.at(channel, cellY, cellX)
                    }
                }
            }
            return Self.convolve(parameters, input: input, count: count)
        }
    }

    /// The three 1 × 1 layers on `count` cells, laid out channel by channel.
    static func convolve(_ parameters: [Float], input: [Float], count: Int) -> [Float] {
        var first = [Float](repeating: 0, count: 8 * count), second = [Float](repeating: 0, count: 8 * count)
        var logits = [Float](repeating: 0, count: count)
        let cells = vDSP_Length(count)
        parameters.withUnsafeBufferPointer { kernel in
            guard let k = kernel.baseAddress else { return }
            vDSP_mmul(k, 1, input, 1, &first, 1, 8, cells, 10)
            addBiasAndRectify(&first, bias: k + 152, rows: 8, columns: count)
            vDSP_mmul(k + 80, 1, first, 1, &second, 1, 8, cells, 8)
            addBiasAndRectify(&second, bias: k + 160, rows: 8, columns: count)
            vDSP_mmul(k + 144, 1, second, 1, &logits, 1, 1, cells, 8)
            var bias = k[168]
            vDSP_vsadd(logits, 1, &bias, &logits, 1, cells)
        }
        return logits
    }

    private static func addBiasAndRectify(_ matrix: inout [Float], bias: UnsafePointer<Float>, rows: Int, columns: Int) {
        matrix.withUnsafeMutableBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return }
            for row in 0..<rows {
                var value = bias[row], zero: Float = 0
                let line = base + row * columns
                vDSP_vsadd(line, 1, &value, line, 1, vDSP_Length(columns))
                vDSP_vthres(line, 1, &zero, line, 1, vDSP_Length(columns))
            }
        }
    }
}
