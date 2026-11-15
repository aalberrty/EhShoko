import UIKit

/// Where the trailer is relative to what the reader is on.
enum ReaderTrailerState: Equatable {
    /// Not what the reader is on.
    case away
    /// On screen in the empty half of the last spread, with the last page.
    case besideLastPage
    /// What the reader is on, without a page.
    case alone
}

/// The plain view that stands in the trailer's place and holds the host's content (the
/// closing page). It is not a page view: nothing that is indexed by page knows it, it is never
/// pooled or recycled, and no zoom, menu or Live Text is attached to it.
final class ReaderTrailerView: UIView {
    private(set) weak var controller: UIViewController?

    init(controller: UIViewController) {
        self.controller = controller
        super.init(frame: .zero)
        backgroundColor = .readerBackground
        clipsToBounds = true
        controller.view.frame = bounds
        controller.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(controller.view)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// The height the content asks for at a width, for the vertical strip. A hosted SwiftUI
    /// view answers this with the height of its layout at that width.
    func fittingHeight(forWidth width: CGFloat) -> CGFloat {
        guard let view = controller?.view, width > 0 else { return 0 }
        let height = view.sizeThatFits(CGSize(width: width, height: 0)).height
        return height.isFinite ? max(height, 0) : 0
    }
}
