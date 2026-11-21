#if DEBUG || HARNESS
import EhCore
import EhFeatures
import UIKit

/// What the harness's gallery shows of its made-up translation.
enum ReaderHarnessTranslationMode: Hashable {
    /// Translate was never pressed: the engine is not to ask for anything.
    case off
    /// Translated, and showing the original.
    case original
    case translated
}

/// The harness's made-up translation of its gallery: a patch file for each page, written
/// ahead with the same code that reads them back (`PageTranslationPatches`), and the part of
/// the reader's model the engine talks to. No model runs and nothing is read from a page.
///
/// The files are in `Library/Caches/ReaderHarness/Translation/`, which the harness empties
/// when it opens.
final class ReaderHarnessTranslation {
    static let directory = ReaderHarnessFiles.directory.appending(path: "Translation", directoryHint: .isDirectory)

    /// The pages that are translated, as the engine is told.
    private(set) var overlays: [Int: PageTranslationOverlay] = [:]
    /// The pages whose file the engine could not read, in the order it said so.
    private(set) var failures: [Int] = []
    /// Pages whose file is written damaged, also when it is "drawn again".
    var damagedPages: Set<Int> = []
    private let folder: URL
    private var making: Task<Void, Never>?

    init() {
        folder = Self.directory.appending(path: UUID().uuidString.prefix(8).lowercased(), directoryHint: .isDirectory)
    }

    func overlay(at page: Int) -> PageTranslationOverlay? {
        overlays[page]
    }

    /// Draws and writes the files of `pages`, in that order and off the main actor, and says
    /// when each page is translated. Returns when all are on disk.
    func make(pages: [Int], onPage: ((Int) -> Void)? = nil) async {
        for page in pages where !Task.isCancelled {
            let url = folder.appending(path: "\(page).patch")
            guard await ReaderHarnessPatches.write(page: page, to: url, isDamaged: damagedPages.contains(page)) else {
                continue
            }
            overlays[page] = PageTranslationOverlay(patchFile: url, variant: "harness.r1")
            onPage?(page)
        }
    }

    /// The same in the background, as pages finish one by one while the reader is open.
    func startMaking(pages: [Int], onPage: @escaping (Int) -> Void) {
        making?.cancel()
        making = Task { [weak self] in await self?.make(pages: pages, onPage: onPage) }
    }

    func stop() {
        making?.cancel()
    }

    /// The engine could not show a page: the page is not translated until it is drawn again.
    func didFail(page: Int) {
        failures.append(page)
        overlays[page] = nil
    }

    /// Cuts a page's file short, as a damaged cache would leave it.
    func damageFile(of page: Int) async {
        guard let url = overlays[page]?.patchFile else { return }
        await ReaderHarnessPatches.damage(url)
    }

    static func removeAll() {
        try? FileManager.default.removeItem(at: directory)
    }
}

// The engine's translation calls, answered from the made-up translation.
extension ReaderHarnessModel {
    func translationOverlay(at page: Int) -> PageTranslationOverlay? {
        recorder?.add("D translationOverlay \(page)")
        return translation?.overlay(at: page)
    }

    /// As the reader's model answers it: the page loses its overlay and is drawn again.
    func readerDidFailToShowTranslation(page: Int) {
        recorder?.add("E translationFailed \(page)")
        ReaderHarnessFiles.log("\(setup.name): the translation of page \(page) could not be shown")
        guard let translation else { return }
        translation.didFail(page: page)
        proxy.reloadTranslation(page)
        let proxy = proxy
        translation.startMaking(pages: [page]) { proxy.reloadTranslation($0) }
    }

    // Not recorded: it is not a page call, and a record must stay comparable with one made
    // before the engine reported it.
    func readerDidChangePagesOnScreen(_ pages: [Int]) {
        pagesOnScreen = pages
    }

    /// The panel's choice. The first time it is not "off" stands for the press of Translate:
    /// from then on pages finish one after another, the current one first.
    func translationModeDidChange() {
        if translationMode != .off, translation == nil {
            let translation = ReaderHarnessTranslation()
            self.translation = translation
            let pages = Array(currentPage...max(galleryPageCount, currentPage)) + Array(1..<currentPage).reversed()
            let proxy = proxy
            translation.startMaking(pages: pages) { proxy.reloadTranslation($0) }
        }
        proxy.setTranslationDisplay(translationMode == .translated ? .translated : .original)
    }
}

/// Draws the made-up patches of a harness page. Each is something whose right place can be
/// read off the page under it, which has a line every 100 pixels and a frame 4 pixels in.
nonisolated enum ReaderHarnessPatches {
    /// The size of the bitmap a page's patches are made on: the page's, cut to four
    /// megapixels as the translation pipeline cuts it. So the large pages of the harness have
    /// patches in pixels that are not the image's, as real ones do.
    static func workingSize(forPage page: Int) -> CGSize {
        let size = ReaderHarnessImages.spec(forPage: page).pixelSize
        let limit: CGFloat = 4_000_000
        guard size.width * size.height > limit else { return size }
        let scale = (limit / (size.width * size.height)).squareRoot()
        return CGSize(width: (size.width * scale).rounded(.down), height: (size.height * scale).rounded(.down))
    }

    /// A page's patches, or `nil` for the animated page, which is never translated.
    static func patches(forPage page: Int) -> PageTranslationPatches? {
        let spec = ReaderHarnessImages.spec(forPage: page)
        guard !spec.isAnimated else { return nil }
        let canvas = Canvas(pageSize: spec.pixelSize, workingSize: workingSize(forPage: page))
        var patches: [PageTranslationPatches.Patch?] = []
        let size = spec.pixelSize

        // "Balloons": white, with the page's lines carried on in magenta. They join the
        // page's own lines at the patch's edges when the overlay is in its place.
        for top in stride(from: 300, through: size.height - 500, by: 1_600) {
            let rect = CGRect(x: 200, y: top, width: min(500, size.width - 300), height: 400)
            patches.append(canvas.patch(rect) { context in
                context.setFillColor(UIColor.white.cgColor)
                context.addPath(CGPath(roundedRect: rect, cornerWidth: 60, cornerHeight: 60, transform: nil))
                context.fillPath()
                drawGrid(in: context, rect: rect, color: .magenta)
                context.setLineWidth(6)
                context.addPath(
                    CGPath(roundedRect: rect.insetBy(dx: 3, dy: 3), cornerWidth: 57, cornerHeight: 57, transform: nil)
                )
                context.strokePath()
                draw("译文 · 第 \(page) 页", in: rect.insetBy(dx: 20, dy: 130), size: 64, color: .black)
                draw("made-up text", in: rect.insetBy(dx: 20, dy: 230), size: 40, color: .darkGray)
            })
        }
        // The four corners: the overlay reaches exactly as far as the page. The red line
        // lies on the page's frame.
        for corner in [
            CGPoint(x: 0, y: 0), CGPoint(x: size.width - 100, y: 0),
            CGPoint(x: 0, y: size.height - 100), CGPoint(x: size.width - 100, y: size.height - 100)
        ] {
            let rect = CGRect(origin: corner, size: CGSize(width: 100, height: 100))
            patches.append(canvas.patch(rect) { context in
                context.setFillColor(UIColor.systemTeal.cgColor)
                context.fill(rect)
                context.setStrokeColor(UIColor.red.cgColor)
                context.setLineWidth(1)
                context.stroke(CGRect(origin: .zero, size: size).insetBy(dx: 4, dy: 4))
            })
        }
        // Lettering alone: the page shows through everywhere else, and half through the disc.
        if size.height >= 1_200, size.width >= 700 {
            let rect = CGRect(x: size.width / 2 - 300, y: 850, width: 600, height: 200)
            patches.append(canvas.patch(rect) { context in
                context.setFillColor(UIColor.blue.withAlphaComponent(0.5).cgColor)
                context.fillEllipse(in: CGRect(x: rect.minX + 10, y: rect.minY + 40, width: 120, height: 120))
                draw("只有文字，底下是原图", in: rect.insetBy(dx: 90, dy: 70).offsetBy(dx: 60, dy: 0), size: 40, color: .red)
            })
        }
        // Two that overlap: the second lies over the first.
        if size.height >= 1_700 {
            let first = CGRect(x: 100, y: 1_300, width: 300, height: 200)
            patches.append(canvas.patch(first) { context in
                context.setFillColor(UIColor.cyan.cgColor)
                context.fill(first)
                draw("1", in: first.insetBy(dx: 20, dy: 40), size: 100, color: .black)
            })
            let second = CGRect(x: 250, y: 1_400, width: 300, height: 200)
            patches.append(canvas.patch(second) { context in
                context.setFillColor(UIColor.yellow.cgColor)
                context.fill(second)
                draw("2", in: second.insetBy(dx: 20, dy: 40), size: 100, color: .black)
            })
        }
        return PageTranslationPatches(pageSize: canvas.workingSize, patches: patches.compactMap(\.self))
    }

    /// Writes a page's patch file. `false` for a page that is not translated.
    @concurrent
    static func write(page: Int, to url: URL, isDamaged: Bool) async -> Bool {
        guard let patches = patches(forPage: page) else { return false }
        do {
            try await patches.write(to: url)
        } catch {
            ReaderHarnessFiles.log("! the patch file of page \(page) was not written: \(error)")
            return false
        }
        if isDamaged {
            await damage(url)
        }
        return true
    }

    /// Leaves the first half of a file.
    @concurrent
    static func damage(_ url: URL) async {
        guard let data = try? Data(contentsOf: url) else { return }
        try? data.prefix(data.count / 2).write(to: url, options: .atomic)
    }

    /// The page's own lines, one pixel wide every 100 pixels, where they cross `rect`.
    private static func drawGrid(in context: CGContext, rect: CGRect, color: UIColor) {
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(1)
        for x in stride(from: (rect.minX / 100).rounded(.up) * 100, to: rect.maxX, by: 100) {
            context.move(to: CGPoint(x: x + 0.5, y: rect.minY))
            context.addLine(to: CGPoint(x: x + 0.5, y: rect.maxY))
        }
        for y in stride(from: (rect.minY / 100).rounded(.up) * 100, to: rect.maxY, by: 100) {
            context.move(to: CGPoint(x: rect.minX, y: y + 0.5))
            context.addLine(to: CGPoint(x: rect.maxX, y: y + 0.5))
        }
        context.strokePath()
    }

    private static func draw(_ text: String, in rect: CGRect, size: CGFloat, color: UIColor) {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        (text as NSString).draw(in: rect, withAttributes: [
            .font: UIFont.systemFont(ofSize: size, weight: .bold), .foregroundColor: color, .paragraphStyle: style
        ])
    }

    /// Draws in the page's own pixels and gives back patches in the working bitmap's.
    nonisolated private struct Canvas {
        var pageSize: CGSize
        var workingSize: CGSize

        func patch(_ rect: CGRect, draw: (CGContext) -> Void) -> PageTranslationPatches.Patch? {
            let scaleX = workingSize.width / pageSize.width
            let scaleY = workingSize.height / pageSize.height
            // Whole pixels of the working bitmap, cut to it; the drawing keeps its exact
            // place inside them.
            let working = CGRect(
                x: rect.minX * scaleX, y: rect.minY * scaleY, width: rect.width * scaleX, height: rect.height * scaleY
            ).integral.intersection(CGRect(origin: .zero, size: workingSize))
            guard working.width >= 1, working.height >= 1 else { return nil }
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            format.opaque = false
            format.preferredRange = .standard
            let image = UIGraphicsImageRenderer(size: working.size, format: format).image { renderer in
                let context = renderer.cgContext
                context.translateBy(x: -working.minX, y: -working.minY)
                context.scaleBy(x: scaleX, y: scaleY)
                context.clip(to: rect)
                draw(context)
            }
            return image.cgImage.map { PageTranslationPatches.Patch(rect: working, image: $0) }
        }
    }
}
#endif
