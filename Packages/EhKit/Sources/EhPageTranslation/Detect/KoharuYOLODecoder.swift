import CoreGraphics
import Foundation

/// The outputs of Koharu YOLO26s-seg's end-to-end head decoded as its ONNX export does: the
/// best 300 anchors by their best class score, then the best 300 (anchor, class) pairs among
/// those; no suppression, which the one-to-one head needs none of. Boxes are corners in input
/// pixels. Classes: 0 frame, 1 dialogue text, 2 balloon, 3 onomatopoeia. The model card's
/// threshold, 0.25, applies to every class.
struct KoharuYOLODecoder: Sendable {
    var maximumDetections = 300
    static let threshold: Float = 0.25

    static func role(of label: Int) -> DetectionRole {
        switch label {
        case 1: .text
        case 2: .balloon
        case 3: .soundEffect
        default: .ignored
        }
    }

    /// `boxes` and `scores` are (1, 4, N), or (1, 4, 168, 128) with the anchors in rows of 128.
    /// Up to `maximumDetections`, best first, before the threshold.
    func decode(boxes: TensorView, scores: TensorView, letterbox: Letterbox) -> [Detection] {
        let count = scores.positions, classes = scores.shape[1]
        guard count > 0, classes > 0, boxes.positions == count, boxes.shape[1] >= 4 else { return [] }
        var values = [Float](repeating: 0, count: classes * count)
        values.withUnsafeMutableBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return }
            for label in 0..<classes { scores.copyRow(label, into: base + label * count) }
        }
        var best = [Float](repeating: 0, count: count)
        for anchor in 0..<count {
            var top = values[anchor]
            for label in 1..<max(classes, 1) { top = max(top, values[label * count + anchor]) }
            best[anchor] = top
        }
        let kept = min(maximumDetections, count)
        let anchors = Self.largest(kept, of: best)
        var pairs: [(score: Float, anchor: Int, label: Int)] = []
        pairs.reserveCapacity(kept * classes)
        for anchor in anchors {
            for label in 0..<classes { pairs.append((values[label * count + anchor], anchor, label)) }
        }
        pairs.sort { $0.score > $1.score || ($0.score == $1.score && $0.anchor < $1.anchor) }
        return pairs.prefix(maximumDetections).map { score, anchor, label in
            let x0 = Double(boxes.at(0, anchor)), y0 = Double(boxes.at(1, anchor))
            let input = CGRect(x: x0, y: y0, width: Double(boxes.at(2, anchor)) - x0, height: Double(boxes.at(3, anchor)) - y0)
            return Detection(box: letterbox.pageRect(fromInput: input), inputBox: input, score: score, label: label, anchor: anchor)
        }
    }

    /// The indices of the `k` largest values, in no particular order (a quickselect).
    static func largest(_ k: Int, of values: [Float]) -> ArraySlice<Int> {
        var indices = Array(values.indices)
        guard k < indices.count else { return indices[...] }
        guard k > 0 else { return [] }
        indices.withUnsafeMutableBufferPointer { b in
            var low = 0, high = b.count - 1
            while low < high {
                let pivot = values[b[(low + high) / 2]]
                var i = low, j = high
                while i <= j {
                    while values[b[i]] > pivot { i += 1 }
                    while values[b[j]] < pivot { j -= 1 }
                    if i <= j {
                        b.swapAt(i, j)
                        i += 1
                        j -= 1
                    }
                }
                if k - 1 <= j { high = j } else if k - 1 >= i { low = i } else { break }
            }
        }
        return indices.prefix(k)
    }

    /// Masks: the sigmoid of the 32 coefficients times the 32 prototypes (P × P, a quarter of the
    /// input), sampled bilinearly and set above 0.5, within 4 input pixels of the box. Only the
    /// prototype cells a mask reads are computed.
    static func masks(coefficients: TensorView, prototypes: TensorView, letterbox: Letterbox) -> MaskSampler {
        let side = prototypes.shape[3], channels = prototypes.shape[1]
        return MaskSampler(letterbox: letterbox, gridSide: side, threshold: 0.5, inclusive: false, margin: 4) {
            detection, window in
            var weights = [Float](repeating: 0, count: channels)
            for channel in 0..<channels { weights[channel] = coefficients.at(channel, detection.anchor) }
            var values = [Float](repeating: 0, count: window.width * window.height)
            for y in 0..<window.height {
                for x in 0..<window.width {
                    var sum: Float = 0
                    for channel in 0..<channels {
                        sum += weights[channel] * prototypes.at(channel, window.y0 + y, window.x0 + x)
                    }
                    values[y * window.width + x] = 1 / (1 + exp(-sum))
                }
            }
            return values
        }
    }
}
