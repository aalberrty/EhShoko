import EhCore
import EhFeatures
import EhModels
import SwiftUI

/// All previews (`ledger.md` section 4, child screens): a grid of thumbnails 70 to 80 wide
/// with the page number under each in small capitals, opened at the page last read. A tap
/// opens the reader there, zooming out of the thumbnail; a thumbnail whose preview failed asks
/// for it again.
struct LedgerPreviewsGrid: View {
    let detail: GalleryDetailModel

    @State private var model: PreviewsModel
    @Environment(StackRouter.self) private var stack: StackRouter?
    @Environment(AppRouter.self) private var appRouter: AppRouter?
    @Environment(\.look) private var look

    init(detail: GalleryDetailModel) {
        self.detail = detail
        _model = State(initialValue: PreviewsModel(
            gallery: detail.gallery, pageCount: detail.pageCount, config: detail.previewConfig,
            previewURLs: detail.previewURLs
        ))
    }

    var body: some View {
        let gid = model.gallery.gid
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 70, maximum: 80), spacing: 12)], spacing: 14) {
                    ForEach(1..<(model.pageCount + 1), id: \.self) { index in
                        Button {
                            model.select(index)
                        } label: {
                            LedgerPreviewCell(
                                index: index, thumbnail: model.preview(at: index), failed: model.hasFailed(at: index)
                            )
                            .equatable()
                            .readerSource(.preview(gid: gid, page: index))
                        }
                        .buttonStyle(.plain)
                        .onAppear { model.thumbnailAppeared(index) }
                        .onDisappear { model.thumbnailDisappeared(index) }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            .onAppear {
                // Opened at the page last read.
                if let page = detail.readingProgress, page > 1, page <= model.pageCount {
                    proxy.scrollTo(page, anchor: .center)
                }
            }
        }
        .background { look.background.ignoresSafeArea() }
        .navigationTitle(L10n.Localizable.PreviewsView.Title.previews)
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load() }
        .readerCover(
            item: reading, detail: detail,
            source: { request in request.page.map { .preview(gid: request.gallery.gid, page: $0) } },
            onExit: leaveReader
        )
        .sensoryFeedback(.impact(weight: .light), trigger: model.readerDestination) { _, destination in
            destination != nil
        }
        .previewsZoomScope()
    }

    /// The reader the grid asked for, as the cover presents it.
    private var reading: Binding<ReadingRequest?> {
        Binding(
            get: {
                guard case .reader(let page)? = model.readerDestination else { return nil }
                return ReadingRequest(gallery: model.gallery, page: page)
            },
            set: { if $0 == nil { model.readerDestination = nil } }
        )
    }

    /// Where the reader's closing page leads from here: back to the gallery page, its
    /// comments, a search, or signing in.
    private func leaveReader(_ exit: ReaderExit) {
        switch exit {
        case .gallery:
            stack?.pop()
        case .comments:
            detail.destination = .comments(scrollTo: nil)
        case .search(let keyword):
            stack?.push(.search(keyword: keyword))
        case .signIn:
            appRouter?.presentSettings([.settings(.account), .settings(.login)])
        }
    }
}

private struct LedgerPreviewCell: View, Equatable {
    let index: Int
    let thumbnail: PreviewThumbnail?
    let failed: Bool

    var body: some View {
        VStack(spacing: 5) {
            LedgerPreviewThumbnail(thumbnail: thumbnail, width: 80, fillsWidth: true, failed: failed)
            Text(index, format: .number)
                .ledgerSmallCaps()
                .monospacedDigit()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.Localizable.Reader.Page.label(index))
        .accessibilityHint(failed ? L10n.Localizable.ErrorView.Button.retry : "")
    }
}
