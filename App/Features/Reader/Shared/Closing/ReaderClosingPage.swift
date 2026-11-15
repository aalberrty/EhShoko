import Dependencies
import EhCore
import EhFeatures
import EhModels
import SwiftUI
import UIKit

/// The one closing page every reader design shows after a gallery's last page
/// (`Design/designs/closing-page.md`): what was just read, the rating, Favourite, and the ways
/// on. It sits in the reading engine's trailing slot, so it is not a page: it has no number,
/// and nothing indexed by page sees it.
///
/// The engine asks for it once, through `makeController(gallery:pageCount:makeDetail:)`, after
/// the first page and at rest within one page of the end, and keeps it for the life of the
/// reader. Until then nothing of it exists. Its data is the presenting gallery page's model,
/// or a model of its own made when it first appears, which then makes the one detail request
/// (`ReaderClosingContext`).
///
/// It is content in the look's colours, never glass, with no gesture on its background, so
/// the engine's tap zones work on every empty part of it (spike S7).
struct ReaderClosingPage: View {
    let gallery: Gallery
    let pageCount: Int
    /// Tells the engine that the content's height changed, for the vertical strip.
    let sizeReporter: ReaderClosingSizeReporter
    /// Makes the page's own detail model, when no gallery page presented the reader.
    let makeDetail: @MainActor (Gallery) -> GalleryDetailModel

    @Environment(\.readerClosingContext) private var context
    /// The look and accent the reader hands its engine's views (`ReaderScreen`).
    @Environment(\.readerPageStyle) private var style
    // The engine is UIKit, so the stores the shell puts in the environment do not reach here.
    @Dependency(\.settings) private var settings
    @Dependency(\.userStore) private var userStore

    /// The detail model made here when no gallery page presented the reader.
    @State private var ownDetail: GalleryDetailModel?

    /// The room, above the bottom safe area, that the column keeps clear for the reader's
    /// controls when they rest at the bottom: Shelf's panel reaches 172 pt above it (E1),
    /// Ledger's resting sheet 151 pt (spike S4). A reader design whose controls rest higher
    /// covers the column. In the vertical strip the closing block is this much taller than
    /// the column, so the column clears the controls when the strip rests at its end.
    static let bottomReserve: CGFloat = 176

    /// The hosting controller the engine puts in its trailing slot.
    ///
    /// - Parameter makeDetail: makes the page's own detail model; the reader harness makes one
    ///   on stand-in dependencies.
    static func makeController(
        gallery: Gallery, pageCount: Int,
        makeDetail: @escaping @MainActor (Gallery) -> GalleryDetailModel = { GalleryDetailModel(gallery: $0) }
    ) -> UIViewController {
        ReaderClosingProbe.asked()
        let reporter = ReaderClosingSizeReporter()
        let page = ReaderClosingPage(
            gallery: gallery, pageCount: pageCount, sizeReporter: reporter, makeDetail: makeDetail
        )
        let controller = UIHostingController(rootView: page)
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
                }
                .padding(.bottom, Self.bottomReserve)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                    sizeReporter.contentHeightDidChange(height)
                }
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .background { Color(uiColor: .readerBackground).ignoresSafeArea() }
        .modifier(ReaderClosingFeedback(detail: ownDetail))
        // `nil` is the look's own tint, which the default accent gives.
        .lookEnvironment(style.look, accent: style.accent ?? .systemBlue)
        .environment(userStore)
        .task { await loadDetail() }
    }

    /// Runs each time the page comes into the window: the engine takes its view out when its
    /// place is no longer tiled and puts it back, and `.task` starts again. Only the first
    /// time, and only when no gallery page presented the reader, is a model made; its load
    /// runs once and outlives this task, and a later call only refreshes the sign-in state.
    private func loadDetail() async {
        guard context?.detail == nil else {
            ReaderClosingProbe.presenterModelShown()
            return
        }
        let model: GalleryDetailModel
        if let ownDetail {
            model = ownDetail
        } else {
            model = makeDetail(gallery)
            ownDetail = model
            ReaderClosingProbe.detailMade()
        }
        await model.load()
    }
}

/// Lets the engine's vertical strip measure the page again when its content's height changes
/// (the "More by" line arrives with the parsed title, text sizes change). The strip measures
/// with `sizeThatFits` and does so again when the controller's preferred size changes.
final class ReaderClosingSizeReporter {
    weak var controller: UIViewController?
    private var height: CGFloat = 0

    func contentHeightDidChange(_ newHeight: CGFloat) {
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
