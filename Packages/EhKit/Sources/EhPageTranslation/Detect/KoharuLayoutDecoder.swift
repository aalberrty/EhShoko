import CoreGraphics
import Foundation

/// The outputs of KoharuLayout RF-DETR-Seg-2XL decoded as rfdetr's post-processor does: the
/// sigmoid of the (1, Q, C) logits, the best 160 (query, class) pairs, boxes as centre and size
/// in 0…1 of the stretched input; then the per-class thresholds of the model's
/// `inference_config.json`. Classes: 0 text, 1 onomatopoeia, 2 bubble, 3 panel.
struct KoharuLayoutDecoder: Sendable {
    var selected = 160
    static let thresholds: [Float] = [0.25, 0.20, 0.50, 0.50]

    static func threshold(for label: Int) -> Float {
        label < thresholds.count ? thresholds[label] : 0.5
    }

    static func role(of label: Int) -> DetectionRole {
        switch label {
        case 0: .text
        case 1: .soundEffect
        case 2: .balloon
        default: .ignored
        }
    }

    /// The best `selected` pairs, best first, before the thresholds.
    func decode(boxes: TensorView, logits: TensorView, letterbox: Letterbox) -> [Detection] {
        let queries = logits.shape[1], classes = logits.shape[2]
        guard queries > 0, classes > 0, boxes.shape[1] >= queries, boxes.shape[2] >= 4 else { return [] }
        var scored: [(score: Float, index: Int)] = []
        scored.reserveCapacity(queries * classes)
        for query in 0..<queries {
            for label in 0..<classes {
                let logit = logits.value(query * logits.strides[1] + label * logits.strides[2])
                scored.append((1 / (1 + exp(-logit)), query * classes + label))
            }
        }
        scored.sort { $0.score > $1.score || ($0.score == $1.score && $0.index < $1.index) }
        let width = Double(letterbox.inputWidth), height = Double(letterbox.inputHeight)
        func box(_ query: Int, _ k: Int) -> Double {
            Double(boxes.value(query * boxes.strides[1] + k * boxes.strides[2]))
        }
        return scored.prefix(selected).map { score, index in
            let query = index / classes
            let cx = box(query, 0), cy = box(query, 1), w = box(query, 2), h = box(query, 3)
            let input = CGRect(x: (cx - w / 2) * width, y: (cy - h / 2) * height, width: w * width, height: h * height)
            return Detection(
                box: letterbox.pageRect(fromInput: input), inputBox: input, score: score, label: index % classes,
                anchor: query
            )
        }
    }

    /// Masks from the (1, Q, M, M) mask logits, set above 0, within 4 input pixels of the box.
    static func masks(_ masks: TensorView, letterbox: Letterbox) -> MaskSampler {
        MaskSampler(letterbox: letterbox, gridSide: masks.shape[3], threshold: 0, inclusive: false, margin: 4) {
            detection, window in masks.window(channel: detection.anchor, window)
        }
    }
}
