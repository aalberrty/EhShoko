import Dependencies
import EhCore
import EhFeatures
import EhModels
import QuartzCore
import SwiftUI
import UIKit

/// The one closing page every reader design shows after a gallery's last page
/// (`Design/designs/closing-page.md`): what was just read, the rating, Favourite, and the ways
/// on. It sits in the reading engine's trailing slot, so it is not a page: it has no number,
/// and nothing indexed by page sees it.
///
/// The engine asks for it once, through `makeController(gallery:pageCount:)`, when it is about
/// to be shown, and keeps it for the life of the reader. Until then nothing of it exists. Its
/// data is the presenting gallery page's model, or a model of its own made when it first
/// appears, which then makes the one detail request (`ReaderClosingContext`).
///
/// It is content in the look's colours, never glass, with no gesture on its background, so
/// the engine's tap zones work on every empty part of it (spike S7).
struct ReaderClosingPage: View {
    let gallery: Gallery
    let pageCount: Int
    /// Tells the engine that the column's height changed, for the vertical strip.
    let sizeReporter: ReaderClosingSizeReporter

    @Environment(\.readerClosingContext) private var context
    /// The look and accent the reader hands its engine's views (`ReaderScreen`).
    @Environment(\.readerPageStyle) private var style
    // The engine is UIKit, so the stores the shell puts in the environment do not reach here.
    @Dependency(\.settings) private var settings
    @Dependency(\.userStore) private var userStore

    /// The detail model made here when no gallery page presented the reader.
    @State private var ownDetail: GalleryDetailModel?

    /// The hosting controller the engine puts in its trailing slot.
    static func makeController(gallery: Gallery, pageCount: Int) -> UIViewController {
        ReaderClosingProbe.asked()
        let reporter = ReaderClosingSizeReporter()
        let controller = UIHostingController(
            rootView: ReaderClosingPage(gallery: gallery, pageCount: pageCount, sizeReporter: reporter)
        )
        // The page draws the reader's background itself; the hosting view adds nothing.
        controller.view.backgroundColor = .clear
        reporter.controller = controller
        return controller
    }

    var body: some View {
        let detail = context?.detail ?? ownDetail
        ReaderClosingSlotLayout {
            ScrollView(.vertical) {
                ReaderClosingColumn(
                    gallery: gallery, pageCount: pageCount, detail: detail,
                    prefersJapaneseTitle: settings.displaysJapaneseTitle,
                    leave: context.map { context in { context.leave(to: $0) } }
                )
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                    ReaderClosingProbe.laidOut(height: height)
                    sizeReporter.columnHeightDidChange(height)
                }
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .background { Color(uiColor: .readerBackground).ignoresSafeArea() }
        .modifier(ReaderClosingFeedback(detail: ownDetail))
        // `nil` is the look's own tint, which the default accent gives.
        .lookEnvironment(style.look, accent: style.accent ?? .systemBlue)
        .environment(userStore)
        .task { await makeOwnDetailIfNeeded() }
    }

    /// The first time the page appears, and only when no gallery page presented the reader:
    /// a detail model of its own, and its one request.
    private func makeOwnDetailIfNeeded() async {
        guard ownDetail == nil else { return }
        guard context?.detail == nil else {
            ReaderClosingProbe.record("shown with the presenting gallery page's model")
            return
        }
        let model = GalleryDetailModel(gallery: gallery)
        ownDetail = model
        ReaderClosingProbe.record("own detail model made, loading")
        await model.load()
    }
}

/// Lets the engine's vertical strip measure the page again when its column's height changes
/// (the "More by" line arrives with the parsed title, text sizes change). The strip measures
/// with `sizeThatFits` and does so again when the controller's preferred size changes.
final class ReaderClosingSizeReporter {
    weak var controller: UIViewController?
    private var height: CGFloat = 0

    func columnHeightDidChange(_ newHeight: CGFloat) {
        guard abs(newHeight - height) >= 0.5, let controller else { return }
        height = newHeight
        // The strip measures again and changes nothing when the height is the one it has.
        controller.preferredContentSize = CGSize(width: controller.view.bounds.width, height: newHeight)
    }
}

/// The haptics and the Favourite tip for a detail model the page made itself. A gallery page
/// that presented the reader keeps doing both for its own model.
private struct ReaderClosingFeedback: ViewModifier {
    let detail: GalleryDetailModel?

    func body(content: Content) -> some View {
        content
            .sensoryFeedback(trigger: detail?.feedback) { _, feedback in
                feedback.map { $0.isSuccess ? .success : .error }
            }
            .onChange(of: detail?.favoriteReport) { _, report in
                if let report { FavoriteTip.record(report) }
            }
    }
}

/// Proves that the closing page makes nothing and requests nothing before the reader reaches
/// it, and times its making: a log line when the engine asks for it, when its column is first
/// laid out, and when it makes its own detail model, which is the request. Once per reader,
/// in debug and harness builds only.
enum ReaderClosingProbe {
    #if DEBUG || HARNESS
    private static var askedAt: Double?
    #endif

    static func record(_ event: String) {
        #if DEBUG || HARNESS
        @Dependency(\.appLogger) var logger
        logger.info("Closing page: \(event)", category: "Reader")
        #endif
    }

    static func asked() {
        #if DEBUG || HARNESS
        askedAt = CACurrentMediaTime()
        record("asked for by the engine")
        #endif
    }

    static func laidOut(height: CGFloat) {
        #if DEBUG || HARNESS
        guard let askedAt else { return }
        self.askedAt = nil
        let milliseconds = (CACurrentMediaTime() - askedAt) * 1000
        record("column laid out \(Int(height.rounded())) pt tall, \(Int(milliseconds.rounded())) ms after it was asked for")
        #endif
    }
}
