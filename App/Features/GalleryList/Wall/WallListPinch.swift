import SwiftUI
import UIKit

/// The pinch that changes the wall's density (`wall.md` section 3): a UIKit pinch recognizer
/// on the grid's own scroll view, added by a view in the grid's background that looks up its
/// ancestors for the `UIScrollView`.
///
/// It is the one arrangement that works (`spikes/S1.md`). At that level UIKit's default
/// holds: the pinch and the scroll view's pan never run together, so whichever recognises
/// first owns the touches. A pinch does not scroll, a two-finger scroll does not change the
/// density, and when the pinch recognises UIKit cancels the touches in the content, so the
/// covers under the fingers are not opened. That also needs the cells to take a tap gesture
/// and not be `Button`s. A SwiftUI `MagnifyGesture`, however attached, opened galleries or
/// scrolled while pinching.
struct WallListPinch: UIViewRepresentable {
    /// `+1` for larger covers (fingers apart), `-1` for smaller.
    let onStep: (Int) -> Void

    /// How far the fingers move apart, or together, before the density changes.
    static let apart: CGFloat = 1.3
    static let together: CGFloat = 0.77

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> AnchorView {
        context.coordinator.onStep = onStep
        let view = AnchorView()
        view.isUserInteractionEnabled = false
        view.coordinator = context.coordinator
        return view
    }

    func updateUIView(_ view: AnchorView, context: Context) {
        context.coordinator.onStep = onStep
    }

    static func dismantleUIView(_ view: AnchorView, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class Coordinator: NSObject {
        var onStep: ((Int) -> Void)?
        private let recognizer = UIPinchGestureRecognizer()
        /// One step per pinch: the next only after the fingers lift. A second step taken
        /// while the first one's offset was still on its way lost the kept row.
        private var hasStepped = false

        override init() {
            super.init()
            recognizer.addTarget(self, action: #selector(pinched(_:)))
        }

        func attach(to scrollView: UIScrollView?) {
            guard recognizer.view !== scrollView else { return }
            detach()
            scrollView?.addGestureRecognizer(recognizer)
        }

        func detach() {
            recognizer.view?.removeGestureRecognizer(recognizer)
        }

        @objc private func pinched(_ recognizer: UIPinchGestureRecognizer) {
            switch recognizer.state {
            case .began:
                hasStepped = false
            case .changed where !hasStepped:
                if recognizer.scale >= WallListPinch.apart {
                    hasStepped = true
                    onStep?(1)
                } else if recognizer.scale <= WallListPinch.together {
                    hasStepped = true
                    onStep?(-1)
                }
            default:
                break
            }
        }
    }

    final class AnchorView: UIView {
        weak var coordinator: Coordinator?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard window != nil else {
                coordinator?.detach()
                return
            }
            var ancestor = superview
            while let view = ancestor, !(view is UIScrollView) {
                ancestor = view.superview
            }
            coordinator?.attach(to: ancestor as? UIScrollView)
        }
    }
}
