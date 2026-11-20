import UIKit

/// A determinate ring: a track and the fraction done, drawn by two shape layers.
///
/// A page shows its download's progress a few times a second (`ImageLoadProgressGate`), so a
/// step forward is filled in over that interval by Core Animation, outside the main thread.
final class ReaderProgressRing: UIView {
    private(set) var progress: CGFloat = 0

    var trackColor: UIColor = .clear {
        didSet { trackLayer.strokeColor = trackColor.cgColor }
    }

    var progressColor: UIColor = .clear {
        didSet { progressLayer.strokeColor = progressColor.cgColor }
    }

    private let trackLayer = CAShapeLayer()
    private let progressLayer = CAShapeLayer()
    private static let lineWidth: CGFloat = 3
    private static let fillKey = "fill"

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        for shape in [trackLayer, progressLayer] {
            shape.fillColor = nil
            shape.lineWidth = Self.lineWidth
            shape.lineCap = .round
            layer.addSublayer(shape)
        }
        progressLayer.strokeEnd = 0
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// Shows `newValue` (0 to 1). `animated` fills a step forward over the interval between
    /// two reports; a step back (a new download) is shown at once.
    func setProgress(_ newValue: CGFloat, animated: Bool) {
        guard newValue != progress else { return }
        let shown = progressLayer.presentation()?.strokeEnd ?? progress
        progress = newValue
        progressLayer.removeAnimation(forKey: Self.fillKey)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        progressLayer.strokeEnd = newValue
        CATransaction.commit()
        guard animated, newValue > shown, !UIAccessibility.isReduceMotionEnabled else { return }
        let fill = CABasicAnimation(keyPath: "strokeEnd")
        fill.fromValue = shown
        fill.toValue = newValue
        fill.duration = ImageLoadProgressGate.interval / .seconds(1)
        fill.timingFunction = CAMediaTimingFunction(name: .linear)
        progressLayer.add(fill, forKey: Self.fillKey)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let inset = Self.lineWidth / 2
        let rect = bounds.insetBy(dx: inset, dy: inset)
        // From the top, clockwise.
        let path = UIBezierPath(
            arcCenter: CGPoint(x: rect.midX, y: rect.midY), radius: min(rect.width, rect.height) / 2,
            startAngle: -.pi / 2, endAngle: 1.5 * .pi, clockwise: true
        ).cgPath
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for shape in [trackLayer, progressLayer] {
            shape.frame = bounds
            shape.path = path
        }
        CATransaction.commit()
    }
}
