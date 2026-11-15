import EhFeatures
import EhModels
import SwiftUI

/// Every page of the gallery as a wall of thumbnails with its number under each
/// (`wall.md` section 4): three across, or five after a pinch together, opened at the page
/// last read. A tap opens the reader at that page, zooming out of the thumbnail.
///
/// Previews load a preview page at a time as their cells appear (`PreviewsModel`).
struct WallPreviewsView: View {
    let detail: GalleryDetailModel

    @State private var model: PreviewsModel
    @State private var density = WallPreviewDensity.large
    /// The wall's own width, which decides the column count.
    @State private var width: CGFloat = 0
    /// The pages on screen. A reference that nothing observes: a cell that comes or goes
    /// must not re-render the wall.
    @State private var visible = WallVisiblePages()
    @State private var isPlaced = false

    @Environment(StackRouter.self) private var stack
    @Environment(AppRouter.self) private var appRouter: AppRouter?
    @Environment(\.look) private var look

    init(detail: GalleryDetailModel) {
        self.detail = detail
        _model = State(initialValue: PreviewsModel(
            gallery: detail.gallery, pageCount: detail.pageCount,
            config: detail.previewConfig, previewURLs: detail.previewURLs
        ))
    }

    var body: some View {
        let columns = density.columns(in: width)
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: columns), spacing: 10
                ) {
                    ForEach(1..<(model.pageCount + 1), id: \.self) { index in
                        WallPreviewCell(
                            index: index, thumbnail: model.preview(at: index), failed: model.hasFailed(at: index),
                            width: density.targetWidth
                        )
                        .equatable()
                        .readerSource(.preview(gid: model.gallery.gid, page: index))
                        // A tap gesture, not a button: under the pinch a button opened the
                        // page under the fingers.
                        .onTapGesture { model.select(index) }
                        .accessibilityAddTraits(.isButton)
                        .onAppear {
                            visible.pages.insert(index)
                            model.thumbnailAppeared(index)
                        }
                        .onDisappear {
                            visible.pages.remove(index)
                            model.thumbnailDisappeared(index)
                        }
                    }
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 12)
                // On the scroll view itself, where a pinch and a scroll never run together.
                .background { WallScrollViewPinch { apart in step(to: apart ? .large : .small) } }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            // The new layout keeps the row that was at the top; nothing is animated.
            .onChange(of: density) {
                if let anchor = visible.anchor {
                    proxy.scrollTo(anchor, anchor: .top)
                }
            }
            .onChange(of: detail.readingProgress, initial: true) { _, page in
                guard !isPlaced, let page else { return }
                isPlaced = true
                if page > 1, page <= model.pageCount {
                    proxy.scrollTo(page, anchor: .center)
                }
            }
        }
        .background(look.background)
        .sensoryFeedback(.selection, trigger: density)
        .navigationTitle(L10n.Localizable.Gallery.previews)
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load() }
        .readerCover(destination: $model.readerDestination, of: detail, source: readerSource, onExit: leaveReader)
        .sensoryFeedback(.impact(weight: .light), trigger: model.readerDestination) { _, destination in
            destination != nil
        }
    }

    /// The thumbnail that was tapped.
    private var readerSource: ReaderSourceID? {
        guard case .reader(let page?) = model.readerDestination else { return nil }
        return .preview(gid: model.gallery.gid, page: page)
    }

    /// One step per pinch, in one transaction without animation: the animated change showed
    /// the old layout at the new offset.
    private func step(to new: WallPreviewDensity) {
        guard new != density else { return }
        visible.anchor = visible.pages.min()
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { density = new }
    }

    /// Where the reader's closing page leads from here: back to the gallery page, which then
    /// goes on where it is asked to.
    private func leaveReader(_ exit: ReaderExit) {
        switch exit {
        case .gallery:
            stack.pop()
        case .comments:
            stack.pop()
            detail.destination = .comments(scrollTo: nil)
        case .search(let keyword):
            stack.push(.search(keyword: keyword))
        case .signIn:
            appRouter?.presentSettings([.settings(.login)])
        }
    }
}

/// The wall's two densities, by the width a cell aims at: three columns and five on a phone.
nonisolated enum WallPreviewDensity: Equatable, Sendable {
    case large, small

    var targetWidth: CGFloat {
        switch self {
        case .large: 136
        case .small: 82
        }
    }

    /// The width divided by the target, to the nearest whole number, at least two.
    func columns(in width: CGFloat) -> Int {
        guard width > 0 else { return self == .large ? 3 : 5 }
        return max(Int((width / targetWidth).rounded()), 2)
    }
}

private final class WallVisiblePages {
    var pages: Set<Int> = []
    /// The page a change of density keeps at the top.
    var anchor: Int?
}

private struct WallPreviewCell: View, Equatable {
    let index: Int
    let thumbnail: PreviewThumbnail?
    let failed: Bool
    let width: CGFloat

    @Environment(\.look) private var look

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.index == rhs.index && lhs.thumbnail == rhs.thumbnail && lhs.failed == rhs.failed
            && lhs.width == rhs.width
    }

    var body: some View {
        VStack(spacing: 4) {
            WallPreviewThumbnail(thumbnail: thumbnail, width: width, failed: failed)
            Text(index, format: .number)
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(look.secondaryLabel)
        }
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.Localizable.Reader.Page.label(index))
        .accessibilityHint(failed ? L10n.Localizable.ErrorView.Button.retry : "")
    }
}
