#if DEBUG || HARNESS
import EhCore
import EhFeatures
import QuartzCore
import UIKit

// What the harness's translation check reads off a reader: its page views, whether they show
// their translation, and where their patches are on screen.
final class WeakBox<Object: AnyObject> {
    weak var object: Object?

    init(_ object: Object?) {
        self.object = object
    }
}

extension ReaderHarnessPatches {
    /// The bytes of a page's patches as bitmaps.
    static func patchBytes(ofPage page: Int) -> Int {
        (patches(forPage: page)?.patches ?? []).reduce(0) { $0 + Int($1.rect.width * $1.rect.height) * 4 }
    }
}

extension ReaderHarnessRun {
    var pageViews: [ReaderPageView] {
        var views: [ReaderPageView] = []
        engine?.content?.forEachPageView { views.append($0) }
        return views.sorted { $0.page < $1.page }
    }

    func pageView(_ page: Int) -> ReaderPageView? {
        engine?.content?.pageView(forPage: page)
    }

    /// Each page that has a view: whether it has an image and patches, and shows them.
    var translationState: String {
        pageViews.map { view in
            let patches = view.translation.view?.layer.sublayers?.count ?? 0
            return "\(view.page):\(view.showsImage ? "image" : "no image"),\(patches) patches,"
                + (view.showsTranslation ? "shown" : "hidden")
        }.joined(separator: " ")
    }

    /// Waits until every page that has a view, an image and a translation shows it.
    @discardableResult
    func waitForTranslations(limit: Double = 10) async -> Bool {
        let started = CACurrentMediaTime()
        while CACurrentMediaTime() - started < limit {
            // A page whose image failed, or is not there yet, has nothing to show it over.
            let waiting = pageViews.filter {
                $0.showsImage && model.translation?.overlay(at: $0.page) != nil && !$0.showsTranslation
            }
            if waiting.isEmpty, pageViews.contains(where: \.showsTranslation) { return true }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return false
    }

    /// Zooms in as a double tap does, on a point of a page given as fractions of its image.
    func zoom(onPage page: Int, at fraction: CGPoint) async {
        guard let content = engine?.content, let pageView = pageView(page) else { return }
        let image = pageView.imageRect
        let point = CGPoint(x: image.minX + image.width * fraction.x, y: image.minY + image.height * fraction.y)
        content.toggleZoom(at: pageView.convert(point, to: content))
        try? await Task.sleep(for: .milliseconds(700))
        await settle()
        await waitForTranslations()
    }
}

extension ReaderPageView {
    /// Where the image is drawn in the page view: fitted and centred, as the image view does it.
    var imageRect: CGRect {
        guard let size = imageView.image?.size, size.width > 0, size.height > 0 else { return .zero }
        let fitted = ReaderGeometry.aspectFitSize(aspectRatio: size.width / size.height, in: bounds.size)
        return CGRect(
            x: bounds.midX - fitted.width / 2, y: bounds.midY - fitted.height / 2, width: fitted.width, height: fitted.height
        )
    }
}

extension ReaderHarnessExpectations {
    /// Every patch of every page that shows its translation is where the page's image has
    /// it: the patch's share of the bitmap it was made on, taken of the image's rectangle on
    /// screen. Compared in the engine's view, so zoom and scrolling are part of it.
    func expectPlaced(_ what: String, _ run: ReaderHarnessRun) {
        guard let host = run.engine?.view else {
            expect(what, false, "no engine")
            return
        }
        var worst = 0.0
        var count = 0
        var problems: [String] = []
        let shown = run.pageViews.filter(\.showsTranslation)
        for pageView in shown {
            guard let overlay = pageView.translation.view,
                  let expected = ReaderHarnessPatches.patches(forPage: pageView.page)
            else { continue }
            let layers = overlay.layer.sublayers ?? []
            if layers.count != expected.patches.count {
                problems.append("page \(pageView.page): \(layers.count) layers for \(expected.patches.count) patches")
                continue
            }
            let image = pageView.convert(pageView.imageRect, to: host)
            for (layer, patch) in zip(layers, expected.patches) {
                let onScreen = overlay.convert(layer.frame, to: host)
                let wanted = CGRect(
                    x: image.minX + patch.rect.minX / expected.pageSize.width * image.width,
                    y: image.minY + patch.rect.minY / expected.pageSize.height * image.height,
                    width: patch.rect.width / expected.pageSize.width * image.width,
                    height: patch.rect.height / expected.pageSize.height * image.height
                )
                worst = max(
                    worst, abs(onScreen.minX - wanted.minX), abs(onScreen.minY - wanted.minY),
                    abs(onScreen.maxX - wanted.maxX), abs(onScreen.maxY - wanted.maxY)
                )
                count += 1
            }
        }
        let zoom = run.engine?.snapshot?.zoomScales.max() ?? 1
        let detail = String(
            format: "%d patches on pages %@, furthest edge %.3f pt off, zoom %.2f, view %.0f×%.0f",
            count, shown.map { "\($0.page)" }.joined(separator: ","), worst, zoom, host.bounds.width, host.bounds.height
        )
        expect(what, problems.isEmpty && count > 0 && worst < 0.1, problems.isEmpty ? detail : problems.joined(separator: "; "))
    }
}
#endif
