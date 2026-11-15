import SwiftUI
import UIKit

/// A finger on the scrub capsule: it begins the moment the finger lands and follows it
/// wherever it goes, off the capsule too, until it lifts.
///
/// A UIKit recognizer because its states are exact. A scrub must end when the finger lifts
/// and also when the system takes the touch away, and SwiftUI's `DragGesture` reports no
/// ending for a touch that is cancelled, which would leave the filmstrip up.
struct WallReaderScrubGesture: UIGestureRecognizerRepresentable {
    enum Touch {
        /// The finger landed, at this place across the window.
        case down(CGFloat)
        case moved(CGFloat)
        case up
        /// The system took the touch away.
        case cancelled
    }

    let isEnabled: Bool
    let onTouch: (Touch) -> Void

    func makeUIGestureRecognizer(context: Context) -> UILongPressGestureRecognizer {
        let recognizer = UILongPressGestureRecognizer()
        // A press with no wait is a touch that reports its landing.
        recognizer.minimumPressDuration = 0
        return recognizer
    }

    func updateUIGestureRecognizer(_ recognizer: UILongPressGestureRecognizer, context: Context) {
        if recognizer.isEnabled != isEnabled {
            recognizer.isEnabled = isEnabled
        }
    }

    func handleUIGestureRecognizerAction(_ recognizer: UILongPressGestureRecognizer, context: Context) {
        // Measured across the window: interactive glass stretches the capsule under the
        // finger, which must not count as the finger moving.
        let x = recognizer.location(in: nil).x
        switch recognizer.state {
        case .began: onTouch(.down(x))
        case .changed: onTouch(.moved(x))
        case .ended: onTouch(.up)
        case .cancelled, .failed: onTouch(.cancelled)
        default: break
        }
    }
}
