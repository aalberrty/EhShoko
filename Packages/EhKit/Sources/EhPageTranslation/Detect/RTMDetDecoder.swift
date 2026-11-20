import Accelerate
import CoreGraphics

/// The outputs of the RTMDet manga layout network (RTMDet-Ins, 4 classes) decoded exactly as the
/// mmdeploy export it was cut from: point priors at strides 8, 16 and 32; distances to the four
/// sides; the best 5,000 anchors by their best class score; suppression for each class (an
/// overlap above 0.6 suppresses, scores above 0.05, at most 200 a class); the best 100 overall.
/// Classes: 0 balloon, 1 panel, 2 text line, 3 other text (sound effects and some handwriting).
struct RTMDetDecoder: Sendable {
    static let strides = [8, 16, 32]
    /// The first layer's 80 weights, the second's 64, the third's 8, then their 8, 8 and 1 biases.
    static let maskParameterCount = 169
    /// FumetoReader's defaults, which the accuracy test used.
    static let thresholds: [Float] = [0.35, 0.5, 0.35, 0.45]

    var preselected = 5000
    var overlap: Float = 0.6
    var minimumScore: Float = 0.05
    var perClass = 200
    var kept = 100
    let inputSize: Int
    /// (x, y, stride) of each anchor, in the network's output order.
    let priors: [SIMD3<Float>]

    init(inputSize: Int) {
        self.inputSize = inputSize
        var priors: [SIMD3<Float>] = []
        for stride in Self.strides {
            let count = inputSize / stride
            for y in 0..<count {
                for x in 0..<count { priors.append(SIMD3(Float(x * stride), Float(y * stride), Float(stride))) }
            }
        }
        self.priors = priors
    }

    static func threshold(for label: Int) -> Float {
        label < thresholds.count ? thresholds[label] : 0.5
    }

    static func role(of label: Int) -> DetectionRole {
        switch label {
        case 0: .balloon
        case 2: .text
        case 3: .soundEffect
        default: .ignored
        }
    }

    /// `scores` and `dists` are (1, 4, N), or (1, 4, 168, 128) with the anchors in rows of 128.
    /// Up to `kept` detections, best first, before the thresholds.
    func decode(scores: TensorView, distances: TensorView, letterbox: Letterbox) -> [Detection] {
        let count = priors.count, classes = scores.shape[1]
        guard scores.positions == count, distances.positions == count, classes > 0, distances.shape[1] >= 4 else { return [] }
        var score = [Float](repeating: 0, count: classes * count), distance = [Float](repeating: 0, count: 4 * count)
        score.withUnsafeMutableBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return }
            for label in 0..<classes { scores.copyRow(label, into: base + label * count) }
        }
        distance.withUnsafeMutableBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return }
            for side in 0..<4 { distances.copyRow(side, into: base + side * count) }
        }
        // An anchor whose best score cannot pass the suppression's threshold never survives.
        var best = [Float](repeating: 0, count: count)
        for anchor in 0..<count {
            var top = score[anchor]
            for label in 1..<max(classes, 1) { top = max(top, score[label * count + anchor]) }
            best[anchor] = top
        }
        var candidates = (0..<count).filter { best[$0] > minimumScore }
        if candidates.count > preselected {
            candidates.sort { best[$0] > best[$1] || (best[$0] == best[$1] && $0 < $1) }
            candidates.removeLast(candidates.count - preselected)
        }
        func box(_ anchor: Int) -> SIMD4<Float> {
            let prior = priors[anchor]
            return SIMD4(
                prior.x - distance[anchor], prior.y - distance[count + anchor],
                prior.x + distance[2 * count + anchor], prior.y + distance[3 * count + anchor]
            )
        }
        var selected: [(score: Float, label: Int, anchor: Int)] = []
        for label in 0..<classes {
            var ranked = candidates.compactMap { anchor -> (Float, Int)? in
                let value = score[label * count + anchor]
                return value > minimumScore ? (value, anchor) : nil
            }
            ranked.sort { $0.0 > $1.0 || ($0.0 == $1.0 && $0.1 < $1.1) }
            var keptBoxes: [SIMD4<Float>] = []
            for (value, anchor) in ranked {
                if keptBoxes.count >= perClass { break }
                let candidate = box(anchor)
                if keptBoxes.contains(where: { Self.overlap($0, candidate) > overlap }) { continue }
                keptBoxes.append(candidate)
                selected.append((value, label, anchor))
            }
        }
        selected.sort { $0.score > $1.score || ($0.score == $1.score && $0.anchor < $1.anchor) }
        return selected.prefix(kept).map { selection in
            let corners = box(selection.anchor)
            let input = CGRect(
                x: Double(corners.x), y: Double(corners.y),
                width: Double(corners.z - corners.x), height: Double(corners.w - corners.y)
            )
            return Detection(
                box: letterbox.pageRect(fromInput: input), inputBox: input, score: selection.score,
                label: selection.label, anchor: selection.anchor
            )
        }
    }

    /// Intersection over union of two corner boxes.
    @inline(__always)
    static func overlap(_ a: SIMD4<Float>, _ b: SIMD4<Float>) -> Float {
        let width = min(a.z, b.z) - max(a.x, b.x), height = min(a.w, b.w) - max(a.y, b.y)
        guard width > 0, height > 0 else { return 0 }
        let shared = width * height
        let union = (a.z - a.x) * (a.w - a.y) + (b.z - b.x) * (b.w - b.y) - shared
        return union > 0 ? shared / union : 0
    }
}
