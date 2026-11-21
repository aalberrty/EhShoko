import EhCore
import UIKit

/// A page's translation, over the page's image: one layer for each patch.
///
/// The page view keeps showing the original image and puts this view above it. Showing the
/// original is hiding this view; nothing is decoded, loaded or laid out for it. The view takes
/// no touches, so Live Text and the page's menu under it work as before.
///
/// **Geometry.** The view's own coordinates are the pixels of the bitmap the patches were
/// made on, so a patch's layer is placed once, on whole pixels, and never again. The page view
/// maps the whole view onto the image's rectangle with `place(over:displayScale:)`, which is a
/// transform: rotation, resizing and zoom move one view and no layer.
///
/// **Compare.** The wipe shows the translation on one side of a line only
/// (`showOnly(fromX:)`): the view's bounds are narrowed to the part of the bitmap right of the
/// line and clip to it. A rectangular clip of an axis-aligned view costs the render server a
/// scissor, not an offscreen pass as a mask layer would, and nothing is drawn or decoded for
/// it: the patches keep their layers and their places.
final class ReaderTranslationOverlayView: UIView {
    /// The size of the bitmap the patches were made on; zero while there are none.
    private(set) var pageSize = CGSize.zero
    private var patchLayers: [CALayer] = []
    /// Whether the patches are drawn from mipmaps: see `place(over:displayScale:)`.
    private var usesMipmaps = false
    /// The rectangle of the superview the bitmap is mapped onto, as last placed.
    private var imageRect = CGRect.zero
    /// While comparing, where the shown part starts, in the bitmap's pixels; `nil` shows all.
    private(set) var visibleFromX: CGFloat?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isOpaque = false
        isHidden = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    var hasPatches: Bool { !patchLayers.isEmpty }

    /// Shows `patches` in place of what was shown. Their images must be ready to draw
    /// (`ReaderTranslationOverlayLoader`): this runs on the main actor and only makes layers.
    func show(_ patches: PageTranslationPatches) {
        clear()
        guard patches.pageSize.width > 0, patches.pageSize.height > 0 else { return }
        pageSize = patches.pageSize
        // Not animated, also inside an animation block of the page view's.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // In the file's order: a later patch lies over an earlier one.
        patchLayers = patches.patches.map { patch in
            let layer = CALayer()
            layer.frame = patch.rect
            layer.contents = patch.image
            layer.contentsGravity = .resize
            layer.minificationFilter = usesMipmaps ? .trilinear : .linear
            self.layer.addSublayer(layer)
            return layer
        }
        CATransaction.commit()
    }

    /// Drops the patches and their images.
    func clear() {
        visibleFromX = nil
        clipsToBounds = false
        guard !patchLayers.isEmpty else { return }
        patchLayers.forEach { $0.removeFromSuperlayer() }
        patchLayers = []
        pageSize = .zero
    }

    /// Shows only the part of the patches right of `x`, in the bitmap's pixels (the
    /// translation's side of the wipe), or all of them for `nil`. Changing it sets the view's
    /// bounds and centre: no layer moves and nothing is drawn, so it can follow a finger.
    func showOnly(fromX x: CGFloat?) {
        let x = x.map { min(max($0, 0), pageSize.width) }
        guard x != visibleFromX else { return }
        visibleFromX = x
        clipsToBounds = x != nil
        layOutVisiblePart()
    }

    /// Maps the patches' bitmap onto `imageRect`, the rectangle of the superview in which the
    /// page's image is drawn.
    func place(over imageRect: CGRect, displayScale: CGFloat) {
        guard pageSize.width > 0, pageSize.height > 0, imageRect.width > 0, imageRect.height > 0 else { return }
        self.imageRect = imageRect
        let scale = layOutVisiblePart()

        // A patch has the page bitmap's resolution, up to four megapixels, and the page may
        // be shown much smaller than that (two pages side by side on a phone). Below half
        // size a plain linear filter skips pixels and thin strokes break up, so the patches
        // are then drawn from mipmaps. Above it mipmaps would only soften the lettering.
        let needsMipmaps = scale.a * max(displayScale, 1) < 0.5
        guard needsMipmaps != usesMipmaps else { return }
        usesMipmaps = needsMipmaps
        patchLayers.forEach { $0.minificationFilter = needsMipmaps ? .trilinear : .linear }
    }

    /// The bounds are the shown part of the bitmap, and the centre is where that part's
    /// middle falls in the image's rectangle, so every patch stays where it was.
    @discardableResult
    private func layOutVisiblePart() -> CGAffineTransform {
        guard pageSize.width > 0, pageSize.height > 0, imageRect.width > 0, imageRect.height > 0 else {
            return transform
        }
        let start = visibleFromX ?? 0
        let shown = CGRect(x: start, y: 0, width: pageSize.width - start, height: pageSize.height)
        let scaleX = imageRect.width / pageSize.width
        let scaleY = imageRect.height / pageSize.height
        let scale = CGAffineTransform(scaleX: scaleX, y: scaleY)
        let centre = CGPoint(x: imageRect.minX + shown.midX * scaleX, y: imageRect.minY + shown.midY * scaleY)
        if bounds != shown { bounds = shown }
        if center != centre { center = centre }
        if transform != scale { transform = scale }
        return scale
    }
}
