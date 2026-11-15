import EhFeatures
import EhModels
import SwiftUI

/// Every page's preview in a grid of 100–120 pt columns, 180–220 pt on regular width
/// (`shelf.md` section 4, "All previews"), opened scrolled to the page last read. A tap opens
/// the reader there, zooming out of the preview.
struct ShelfPreviewsScreen: View {
    let detail: GalleryDetailModel

    @State private var model: PreviewsModel
    /// The page the grid is scrolled to: the page last read when it opens.
    @State private var position: Int?

    @Environment(StackRouter.self) private var stack: StackRouter?
    @Environment(AppRouter.self) private var appRouter: AppRouter?
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.look) private var look

    init(detail: GalleryDetailModel) {
        self.detail = detail
        _model = State(initialValue: PreviewsModel(
            gallery: detail.gallery, pageCount: detail.pageCount,
            config: detail.previewConfig, previewURLs: detail.previewURLs
        ))
        _position = State(initialValue: detail.readingProgress.flatMap { $0 > 1 ? $0 : nil })
    }

    var body: some View {
        let widths = Tokens.ImageSize.previewWidths(for: sizeClass)
        let gid = model.gallery.gid
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: widths.lowerBound, maximum: widths.upperBound), spacing: 10)],
                spacing: Tokens.Spacing.medium
            ) {
                ForEach(1..<(model.pageCount + 1), id: \.self) { index in
                    Button {
                        model.select(index)
                    } label: {
                        ShelfPreviewGridCell(
                            index: index, thumbnail: model.preview(at: index), failed: model.hasFailed(at: index),
                            isCurrent: index == lastRead
                        )
                        .readerSource(.preview(gid: gid, page: index))
                    }
                    .buttonStyle(.plain)
                    .onAppear { model.thumbnailAppeared(index) }
                    .onDisappear { model.thumbnailDisappeared(index) }
                }
            }
            .scrollTargetLayout()
            .padding(.horizontal)
            .padding(.vertical, Tokens.Spacing.small)
        }
        .scrollPosition(id: $position, anchor: .center)
        .background(look.background)
        .navigationTitle(L10n.Localizable.PreviewsView.Title.previews)
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load() }
        .readerCover(item: reading, detail: detail, source: { request in
            .preview(gid: gid, page: request.page ?? 1)
        }, onExit: leaveReader)
        .sensoryFeedback(.impact(weight: .light), trigger: model.readerDestination) { _, destination in
            destination != nil
        }
        .previewsZoomScope()
    }

    /// The page last read when the grid opened.
    private var lastRead: Int {
        detail.readingProgress ?? 0
    }

    private var reading: Binding<ReadingRequest?> {
        Binding(
            get: {
                guard case .reader(let page)? = model.readerDestination else { return nil }
                return ReadingRequest(gallery: model.gallery, page: page)
            },
            set: { request in
                if request == nil { model.readerDestination = nil }
            }
        )
    }

    /// Where the reader's closing page leads: back to the gallery page, or on from there.
    private func leaveReader(_ exit: ReaderExit) {
        switch exit {
        case .gallery:
            stack?.pop()
        case .comments:
            stack?.pop()
            detail.destination = .comments(scrollTo: nil)
        case .search(let keyword):
            stack?.push(.search(keyword: keyword))
        case .signIn:
            appRouter?.presentSettings([.settings(.account), .settings(.login)])
        }
    }
}

private struct ShelfPreviewGridCell: View, Equatable {
    let index: Int
    let thumbnail: PreviewThumbnail?
    let failed: Bool
    let isCurrent: Bool

    @Environment(\.look) private var look

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.index == rhs.index && lhs.thumbnail == rhs.thumbnail && lhs.failed == rhs.failed
            && lhs.isCurrent == rhs.isCurrent
    }

    var body: some View {
        VStack(spacing: Tokens.Spacing.xSmall) {
            PreviewThumbnailView(thumbnail: thumbnail, failed: failed)
                .clipShape(.rect(cornerRadius: 6, style: .continuous))
                .overlay {
                    if isCurrent {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .inset(by: -3)
                            .strokeBorder(.tint, lineWidth: 2.5)
                    }
                }
            Text(index, format: .number)
                .font(.caption.weight(isCurrent ? .semibold : .regular))
                .monospacedDigit()
                .foregroundStyle(isCurrent ? AnyShapeStyle(.tint) : AnyShapeStyle(look.secondaryLabel))
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
        .accessibilityHint(failed ? L10n.Localizable.ErrorView.Button.retry : "")
    }
}
