import EhCore
import EhFeatures
import UIKit

/// What a page view keeps of its page's translation.
struct ReaderPageTranslation {
    /// The overlay the page view was last given, whether it is loading, shown or could not
    /// be read.
    var overlay: PageTranslationOverlay?
    /// Whether the reader shows translations: its display is not the original.
    var isDisplayed = false
    /// Made when the first patches arrive. A page view that waits in a pool keeps it, empty.
    var view: ReaderTranslationOverlayView?
    /// The compare wipe's line while the reader compares, `nil` otherwise.
    var wipe: ReaderTranslationWipeLine?
}

/// Where the compare wipe's line is: a vertical line fixed on the screen, at `fraction` of the
/// width of `space` (the engine's view), with the translation on its right. The pages move
/// under it, so each page view converts it into its own overlay's pixels whenever it or the
/// page moves (`ReaderPageView.placeTranslationWipe()`).
struct ReaderTranslationWipeLine {
    var fraction: CGFloat
    weak var space: UIView?
}

// The page's translation: an overlay above its image. The page view loads the overlay's patch
// file when it is given one and drops the patches when it is reused, so they live exactly as
// long as the page has a view. The image, its loading and its decoding know nothing of it.
extension ReaderPageView {
    /// Whether the translation is what the page shows now.
    var showsTranslation: Bool { translation.view?.isHidden == false }

    /// The page's overlay, or `nil` for a page without a translation. The same overlay again
    /// changes nothing; another one is read off the main actor and shown when it is ready,
    /// over the image once there is one.
    func setTranslation(_ overlay: PageTranslationOverlay?, isDisplayed: Bool) {
        translation.isDisplayed = isDisplayed
        guard overlay != translation.overlay else {
            updateTranslationVisibility(animated: false)
            return
        }
        translationLoad?.cancel()
        translationLoad = nil
        translation.overlay = overlay
        translation.view?.clear()
        updateTranslationVisibility(animated: false)
        guard let overlay else { return }
        translationLoad = Task { [weak self] in
            do {
                let patches = try await ReaderTranslationOverlayLoader.load(overlay)
                // A load that was replaced or cancelled ends without touching the view.
                guard !Task.isCancelled, let self, translation.overlay == overlay else { return }
                translationLoad = nil
                show(patches)
            } catch {
                guard !Task.isCancelled, !(error is CancellationError), let self, translation.overlay == overlay
                else { return }
                // The overlay stays set: asked for again, the same file is not read again.
                translationLoad = nil
                delegate?.pageView(self, didFailToShowTranslation: overlay)
            }
        }
    }

    /// Switches between the original and the translation. It hides or shows one view: no
    /// load, no decode and no layout, so it can follow a finger.
    func setTranslationDisplayed(_ isDisplayed: Bool) {
        guard isDisplayed != translation.isDisplayed else { return }
        translation.isDisplayed = isDisplayed
        updateTranslationVisibility(animated: false)
    }

    /// The image was shown, replaced by a sharper decode, or taken away. The overlay shows
    /// only over an image, and comes in with it.
    func translationImageDidChange(animated: Bool) {
        placeTranslation()
        updateTranslationVisibility(animated: animated)
    }

    /// The page view goes back to the pool: nothing of the page's translation stays.
    func dropTranslation() {
        translationLoad?.cancel()
        translationLoad = nil
        translation.overlay = nil
        translation.isDisplayed = false
        translation.wipe = nil
        translation.view?.clear()
        updateTranslationVisibility(animated: false)
    }

    /// The compare wipe's line, or `nil` when the reader does not compare: the overlay then
    /// shows all of its patches again.
    func setTranslationWipe(_ wipe: ReaderTranslationWipeLine?) {
        translation.wipe = wipe
        placeTranslationWipe()
    }

    /// Lets the overlay show only the translation's side of the wipe's line, where the line
    /// falls on this page now. Called when the line moves, when the page moves under it
    /// (scrolling, zoom, a turn: `ReaderContentHost.contentDidMove()`) and when the overlay is
    /// laid out. One conversion and, when the place changed, a view's bounds and centre.
    func placeTranslationWipe() {
        guard let view = translation.view, view.hasPatches else { return }
        guard let wipe = translation.wipe, let space = wipe.space, let window, space.window === window else {
            view.showOnly(fromX: nil)
            return
        }
        let line = CGPoint(x: space.bounds.minX + space.bounds.width * wipe.fraction, y: space.bounds.midY)
        view.showOnly(fromX: view.convert(line, from: space).x)
    }

    /// Lays the overlay over the rectangle the image is drawn in.
    func placeTranslation() {
        guard let view = translation.view, view.hasPatches, let size = imageView.image?.size,
              size.width > 0, size.height > 0
        else { return }
        // The image view fills the page view and fits its image, centred.
        let fitted = ReaderGeometry.aspectFitSize(aspectRatio: size.width / size.height, in: bounds.size)
        let imageRect = CGRect(
            x: bounds.midX - fitted.width / 2, y: bounds.midY - fitted.height / 2,
            width: fitted.width, height: fitted.height
        )
        view.place(over: imageRect, displayScale: traitCollection.displayScale)
        placeTranslationWipe()
    }

    private func show(_ patches: PageTranslationPatches) {
        let view: ReaderTranslationOverlayView
        if let existing = translation.view {
            view = existing
        } else {
            view = ReaderTranslationOverlayView()
            insertSubview(view, aboveSubview: imageView)
            translation.view = view
        }
        view.show(patches)
        // Its first place is not a move, whatever animation this happens to run inside.
        UIView.performWithoutAnimation { placeTranslation() }
        // Like the image, a translation that arrives fades in.
        updateTranslationVisibility(animated: true)
    }

    private func updateTranslationVisibility(animated: Bool) {
        guard let view = translation.view else { return }
        let shows = translation.isDisplayed && showsImage && view.hasPatches
        if shows == view.isHidden {
            view.layer.removeAllAnimations()
            view.alpha = 1
            view.isHidden = !shows
            // With Reduce Motion the translation is simply there, as the page's own
            // controls are (`README` 7.1).
            if shows, animated, !UIAccessibility.isReduceMotionEnabled {
                view.alpha = 0
                UIView.animate(withDuration: 0.2, delay: 0, options: [.allowUserInteraction, .beginFromCurrentState]) {
                    view.alpha = 1
                }
            }
        }
        setLiveTextSuspended(shows)
    }
}
