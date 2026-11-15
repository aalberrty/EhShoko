import CoreGraphics
import Foundation

/// Where a layer of the stage is at one moment: the three things a storyboard changes
/// (`tools/anim.py`: opacity and a transform of a translation and a scale), in grid units.
nonisolated struct LayerPose: Equatable, Sendable {
    var opacity: Double = 1
    var x: CGFloat = 0
    var y: CGFloat = 0
    var scale: CGFloat = 1

    /// Shown in place.
    static let rest = LayerPose()

    /// `opacity` alone; the generator's `O`.
    static func fade(_ opacity: Double) -> LayerPose { LayerPose(opacity: opacity) }
    /// Moved down by `y`; the generator's `Y`.
    static func down(_ y: CGFloat, _ opacity: Double = 1) -> LayerPose { LayerPose(opacity: opacity, y: y) }
    /// Moved right by `x`; the generator's `X`.
    static func across(_ x: CGFloat, _ opacity: Double = 1) -> LayerPose { LayerPose(opacity: opacity, x: x) }
    /// Scaled about the layer's origin; the generator's `Z`.
    static func zoom(_ scale: CGFloat, _ opacity: Double = 1) -> LayerPose { LayerPose(opacity: opacity, scale: scale) }

    static func mix(_ from: LayerPose, _ to: LayerPose, _ progress: Double) -> LayerPose {
        let p = CGFloat(progress)
        return LayerPose(
            opacity: from.opacity + (to.opacity - from.opacity) * progress,
            x: from.x + (to.x - from.x) * p,
            y: from.y + (to.y - from.y) * p,
            scale: from.scale + (to.scale - from.scale) * p
        )
    }
}

/// A pose at a time of a storyboard, in seconds from the start of its eight.
nonisolated struct Keyframe: Sendable {
    let time: TimeInterval
    let pose: LayerPose

    init(_ time: TimeInterval, _ pose: LayerPose) {
        self.time = time
        self.pose = pose
    }
}

/// Keyframes in time order. Between two of them the pose eases in and out, as every interval
/// of the generator's CSS does (`ease-in-out`); before the first and after the last it holds.
nonisolated struct KeyframeTrack: Sendable {
    let keyframes: [Keyframe]

    init(_ keyframes: [Keyframe]) {
        self.keyframes = keyframes.sorted { $0.time < $1.time }
    }

    func pose(at time: TimeInterval) -> LayerPose {
        guard let first = keyframes.first, let last = keyframes.last else { return .rest }
        if time <= first.time { return first.pose }
        if time >= last.time { return last.pose }
        // Fewer than a dozen keyframes per layer: a scan is cheaper than a search.
        var index = 1
        while keyframes[index].time < time { index += 1 }
        let from = keyframes[index - 1], to = keyframes[index]
        let span = to.time - from.time
        guard span > 0 else { return to.pose }
        return LayerPose.mix(from.pose, to.pose, Easing.inOut((time - from.time) / span))
    }
}

nonisolated enum Easing {
    /// CSS `ease-in-out`, `cubic-bezier(0.42, 0, 0.58, 1)`, for a progress in 0...1.
    static func inOut(_ progress: Double) -> Double {
        let x = min(max(progress, 0), 1)
        guard x > 0, x < 1 else { return x }
        // Solve bezierX(t) = x by Newton's method, falling back to bisection where the slope
        // is flat; then the eased value is bezierY(t).
        var t = x
        for _ in 0..<6 {
            let error = bezier(t, 0.42, 0.58) - x
            if abs(error) < 1e-6 { return bezier(t, 0, 1) }
            let slope = bezierSlope(t, 0.42, 0.58)
            guard abs(slope) > 1e-6 else { break }
            t -= error / slope
        }
        var low = 0.0, high = 1.0
        t = x
        for _ in 0..<20 {
            let value = bezier(t, 0.42, 0.58)
            if abs(value - x) < 1e-6 { break }
            if value < x { low = t } else { high = t }
            t = (low + high) / 2
        }
        return bezier(t, 0, 1)
    }

    /// One coordinate of a cubic Bézier from 0 to 1 with control values `a` and `b`.
    private static func bezier(_ t: Double, _ a: Double, _ b: Double) -> Double {
        let u = 1 - t
        return 3 * u * u * t * a + 3 * u * t * t * b + t * t * t
    }

    private static func bezierSlope(_ t: Double, _ a: Double, _ b: Double) -> Double {
        let u = 1 - t
        return 3 * u * u * a + 6 * u * t * (b - a) + 3 * t * t * (1 - b)
    }
}
