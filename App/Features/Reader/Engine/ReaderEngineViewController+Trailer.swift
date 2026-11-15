import UIKit

// The engine's side of the trailer, the one thing after the last page that is not a page (the
// closing page). The two layouts say where it is, the scroll view of the reading mode places
// its view, and the engine owns that view and tells the host when the reader is on it.
// Nothing that takes or returns a page number is involved, so nothing indexed by page (the
// prefetcher, the registry, decoding, the page menu, Live Text) can see it.
extension ReaderEngineViewController {
    /// The view for the trailer's place, making its content the first time the moment is right.
    ///
    /// Making the content (a hosting controller and its first layout) takes longer than a
    /// frame. So it is made while the scroll view rests, where the frame it costs shows
    /// nothing moving, and not before the reader's first page is up, which it would hold
    /// back. A place that is already on screen cannot wait for rest. Before the first page
    /// only the reader's own scrolling counts for that: an opening layout that happens to
    /// show the place (a strip shorter than the screen, a last page with the trailer beside
    /// it) leaves it empty until the first page has settled.
    func trailerView(isOnScreen: Bool, isMoving: Bool) -> ReaderTrailerView? {
        if let trailer { return trailer }
        guard hasTrailer else { return nil }
        let isTheMoment = hasSettledFirstPage ? isOnScreen || !isMoving : isOnScreen && isMoving
        guard isTheMoment else { return nil }
        // Asked once. A host that has no content after all gets an empty place.
        let controller = dataSource?.makeTrailerViewController()
        if let controller {
            addChild(controller)
        }
        let view = ReaderTrailerView(controller: controller)
        controller?.didMove(toParent: self)
        trailer = view
        return view
    }

    func trailerFittingHeight(forWidth width: CGFloat) -> CGFloat {
        trailer?.fittingHeight(forWidth: width) ?? 0
    }

    func contentDidChangeTrailer(_ state: ReaderTrailerState) {
        switch state {
        case .alone: staysOnTrailer = true
        case .away: staysOnTrailer = false
        // Both are on screen: a new layout goes to whichever the reader came from.
        case .besideLastPage: break
        }
        let isCurrent = state != .away
        guard isCurrent != isTrailerCurrent else { return }
        isTrailerCurrent = isCurrent
        delegate?.readerDidChangeTrailerVisibility(isCurrent)
    }

    /// The reader's first page is up, or has failed: from now on the trailer's content may be
    /// made at rest, and at once where its place is on screen.
    func firstPageDidSettle() {
        guard !hasSettledFirstPage else { return }
        hasSettledFirstPage = true
        guard hasTrailer, trailer == nil else { return }
        // A frame later, so that making the content is not part of the pass that puts the
        // first page on screen.
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(16))
            self?.content?.placeTrailerIfNeeded()
        }
    }

    /// Takes the trailer down: a reload found that the host has none any more.
    func discardTrailer() {
        contentDidChangeTrailer(.away)
        guard let trailer else { return }
        self.trailer = nil
        trailer.controller?.willMove(toParent: nil)
        trailer.removeFromSuperview()
        trailer.controller?.removeFromParent()
    }
}
