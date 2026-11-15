import UIKit

/// Where the trailer is relative to what the reader is on.
enum ReaderTrailerState: Equatable {
    /// Not what the reader is on.
    case away
    /// On screen beside a last page that is alone: the reader is on both.
    case besideLastPage
    /// What the reader is on, without a page.
    case alone
}

/// The plain view that stands in the trailer's place and holds the host's content.
///
/// It is not a page view. Nothing that is indexed by page knows it, it is never pooled or
/// recycled, and it has no zoom, menu or Live Text. One exists per engine; the scroll view of
/// the reading mode adds it while its place is tiled and takes it out again.
final class ReaderTrailerView: UIView {
    private(set) weak var controller: UIViewController?

    /// `controller` is `nil` for a host that announced a trailer and has no content for it.
    init(controller: UIViewController?) {
        self.controller = controller
        super.init(frame: .zero)
        // What shows where the content draws nothing.
        backgroundColor = .readerBackground
        clipsToBounds = true
        guard let view = controller?.view else { return }
        view.frame = bounds
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(view)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// The height the content asks for at a width, for the vertical strip. A hosted SwiftUI
    /// view answers a height of 0 with the height of its layout at that width.
    func fittingHeight(forWidth width: CGFloat) -> CGFloat {
        guard let view = controller?.view, width > 0 else { return 0 }
        let height = view.sizeThatFits(CGSize(width: width, height: 0)).height
        return height.isFinite ? max(height, 0) : 0
    }
}
