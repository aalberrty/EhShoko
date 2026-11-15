import SwiftUI
import UIKit

/// A pinch on a wall of thumbnails: fingers apart for larger ones, together for smaller, one
/// step per pinch (spike S1). The recognizer goes on the grid's own `UIScrollView`, found from a
/// view in the grid's background: there UIKit lets a pinch or the scroll own the touches,
/// never both, and the cells, which take a tap gesture, do not fire under the fingers.
struct WallScrollViewPinch: UIViewRepresentable {
    /// `true` when the fingers moved apart.
    let onStep: (Bool) -> Void

    func makeCoordinator() -> WallPinchCoordinator {
        WallPinchCoordinator()
    }

    func makeUIView(context: Context) -> WallPinchSourceView {
        let view = WallPinchSourceView()
        view.coordinator = context.coordinator
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: WallPinchSourceView, context: Context) {
        context.coordinator.onStep = onStep
    }

    static func dismantleUIView(_ view: WallPinchSourceView, coordinator: WallPinchCoordinator) {
        coordinator.detach()
    }
}

final class WallPinchCoordinator: NSObject {
    var onStep: (Bool) -> Void = { _ in }
    private var hasStepped = false
    private weak var scrollView: UIScrollView?
    private lazy var recognizer = UIPinchGestureRecognizer(target: self, action: #selector(pinched(_:)))

    func attach(to scrollView: UIScrollView) {
        guard self.scrollView !== scrollView else { return }
        detach()
        scrollView.addGestureRecognizer(recognizer)
        self.scrollView = scrollView
    }

    func detach() {
        scrollView?.removeGestureRecognizer(recognizer)
        scrollView = nil
    }

    @objc private func pinched(_ recognizer: UIPinchGestureRecognizer) {
        switch recognizer.state {
        case .began:
            hasStepped = false
        case .changed where !hasStepped:
            if recognizer.scale >= 1.3 {
                hasStepped = true
                onStep(true)
            } else if recognizer.scale <= 0.77 {
                hasStepped = true
                onStep(false)
            }
        default:
            break
        }
    }
}

/// Finds the scroll view it is in once it is in a window, and hands it to the coordinator.
final class WallPinchSourceView: UIView {
    weak var coordinator: WallPinchCoordinator?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else { return }
        var view = superview
        while let current = view, !(current is UIScrollView) {
            view = current.superview
        }
        if let scrollView = view as? UIScrollView {
            coordinator?.attach(to: scrollView)
        }
    }
}
