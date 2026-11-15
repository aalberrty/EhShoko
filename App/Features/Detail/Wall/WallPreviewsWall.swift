import EhCore
import EhFeatures
import EhModels
import SwiftUI

/// All previews (`wall.md` section 4, "Child screens"): a wall of page thumbnails with the
/// page number under each, opened at the page last read. Pinching apart shows three across,
/// together five (more on a wider screen), as on Wall's lists; the top bar's menu has the same
/// two for people who cannot pinch. A tap opens the reader at that page, zooming out of its
/// thumbnail.
///
/// The pinch is a UIKit recognizer on the scroll view and the thumbnails take a tap gesture,
/// not a `Button`: a button under a pinching finger fires when the finger lifts. The change is
/// made at once, with the row at the top kept and a short cue on the wall as a whole; laying
/// the grid out again inside an animation showed the old layout at the new offset.
struct WallPreviewsWall: View {
    let detail: GalleryDetailModel
    /// The page the wall opens at: the page last read when it was opened.
    private let opensAt: Int?

    @State private var model: PreviewsModel
    @State private var isDense = false
    @State private var position: ScrollPosition
    /// How far the wall is scrolled, kept outside SwiftUI's state so that scrolling
    /// invalidates nothing.
    @State private var scroll = WallPreviewsScroll()
    @State private var width: CGFloat = 0
    @State private var cue = WallPreviewsCue.rest
    @State private var hud: HUDConfiguration?
    @State private var stepCount = 0

    @Environment(StackRouter.self) private var stack: StackRouter?
    @Environment(AppRouter.self) private var appRouter: AppRouter?
    @Environment(\.chrome) private var chrome
    @Environment(\.look) private var look
    @ScaledMetric(relativeTo: .caption2) private var numberHeight: CGFloat = 14

    init(detail: GalleryDetailModel) {
        self.detail = detail
        _model = State(initialValue: PreviewsModel(
            gallery: detail.gallery, pageCount: detail.pageCount,
            config: detail.previewConfig, previewURLs: detail.previewURLs
        ))
        let lastRead = detail.readingProgress ?? 0
        opensAt = lastRead > 1 ? lastRead : nil
        _position = State(
            initialValue: lastRead > 1 ? ScrollPosition(id: lastRead, anchor: .center) : ScrollPosition(idType: Int.self)
        )
    }

    var body: some View {
        let layout = WallPreviewsLayout(isDense: isDense, width: width, numberHeight: numberHeight)
        let gid = model.gallery.gid
        let lastRead = detail.readingProgress ?? 0
        ScrollView {
            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.flexible(), spacing: WallPreviewsLayout.columnSpacing), count: layout.columns
                ),
                spacing: WallPreviewsLayout.rowSpacing
            ) {
                ForEach(1..<(model.pageCount + 1), id: \.self) { index in
                    WallPreviewCell(
                        index: index, thumbnail: model.preview(at: index), failed: model.hasFailed(at: index),
                        isCurrent: index == lastRead, numberHeight: numberHeight
                    )
                    .equatable()
                    .readerSource(.preview(gid: gid, page: index))
                    .contentShape(.rect)
                    .onTapGesture { model.select(index) }
                    .onAppear { model.thumbnailAppeared(index) }
                    .onDisappear { model.thumbnailDisappeared(index) }
                }
            }
            .scrollTargetLayout()
            .padding(.horizontal, WallPreviewsLayout.margin)
            .padding(.vertical, WallPreviewsLayout.rowSpacing)
            // Adds itself to the scroll view above it.
            .background { WallPreviewsPinch { step(dense: $0 < 0) } }
        }
        .scrollPosition($position)
        .onScrollGeometryChange(for: WallPreviewsScroll.Mark.self) { geometry in
            WallPreviewsScroll.Mark(
                offset: geometry.contentOffset.y, inset: geometry.contentInsets.top,
                bottomInset: geometry.contentInsets.bottom, container: geometry.containerSize,
                contentHeight: geometry.contentSize.height
            )
        } action: { _, mark in
            scroll.mark = mark
            openAtPageLastRead(mark)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .scaleEffect(cue.scale)
        .opacity(cue.opacity)
        .background { (chrome.isSidePane ? look.surface : look.background).ignoresSafeArea() }
        .navigationTitle(L10n.Localizable.PreviewsView.Title.previews)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { densityMenu }
        }
        .task { await model.load() }
        .readerCover(item: reading, detail: detail, source: { request in
            .preview(gid: gid, page: request.page ?? 1)
        }, onExit: leaveReader)
        .hud($hud)
        .sensoryFeedback(.impact(weight: .light), trigger: model.readerDestination) { _, destination in
            destination != nil
        }
        .sensoryFeedback(.selection, trigger: stepCount)
        .previewsZoomScope()
    }

    // MARK: Opening

    /// iOS 18 does not take a page as the first position of a grid that has not been laid out
    /// and opens at the top, so once the grid has its size the page last read is brought to
    /// the middle by its offset. iOS 26 is there in its first frame, and nothing moves.
    private func openAtPageLastRead(_ mark: WallPreviewsScroll.Mark) {
        guard let opensAt, !scroll.hasOpened, mark.container.height > 0, mark.contentHeight > mark.container.height
        else { return }
        scroll.hasOpened = true
        guard mark.offset + mark.inset < 1 else { return }
        let layout = WallPreviewsLayout(isDense: isDense, width: mark.container.width, numberHeight: numberHeight)
        let rowHeight = layout.pitch - WallPreviewsLayout.rowSpacing
        let rowTop = WallPreviewsLayout.rowSpacing + CGFloat((opensAt - 1) / layout.columns) * layout.pitch
        let visible = mark.container.height - mark.inset - mark.bottomInset
        let centred = rowTop + rowHeight / 2 - mark.inset - visible / 2
        let offset = min(centred, mark.contentHeight - mark.container.height + mark.bottomInset)
        guard offset > -mark.inset + 1 else { return }
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) { position.scrollTo(y: offset) }
    }

    // MARK: Density

    /// The two widths by their column counts, for people who cannot pinch.
    private var densityMenu: some View {
        let columns = WallPreviewsLayout(isDense: isDense, width: width, numberHeight: numberHeight).columns
        return Menu {
            Picker(selection: Binding(get: { isDense }, set: { step(dense: $0) })) {
                ForEach([false, true], id: \.self) { dense in
                    Text(L10n.Localizable.List.Density.columns(
                        WallPreviewsLayout(isDense: dense, width: width, numberHeight: numberHeight).columns
                    ))
                    .tag(dense)
                }
            } label: {
                EmptyView()
            }
            .pickerStyle(.inline)
        } label: {
            Label(L10n.Localizable.List.Density.columns(columns), systemImage: "square.grid.2x2")
        }
    }

    /// Changes the width of the thumbnails at once, keeping the row at the top where it is.
    private func step(dense: Bool) {
        guard dense != isDense, width > 0 else { return }
        let old = WallPreviewsLayout(isDense: isDense, width: width, numberHeight: numberHeight)
        let new = WallPreviewsLayout(isDense: dense, width: width, numberHeight: numberHeight)
        // The row nearest the top edge, and the row its first page is in afterwards. Every row
        // of a layout is one height, so the offset is worked out, not looked up: scrolling to
        // the page by its identity landed a row early once the grid had been laid out anew.
        let row = Int((max(scroll.mark.offset + scroll.mark.inset, 0) / old.pitch).rounded())
        let anchor = min(row * old.columns, max(model.pageCount - 1, 0))
        // An offset counts from the scroll view's own top edge, which is under the top bar.
        let offset = CGFloat(anchor / new.columns) * new.pitch - scroll.mark.inset
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            isDense = dense
            position.scrollTo(y: offset)
            cue = WallPreviewsCue(scale: min(max(old.pitch / new.pitch, 0.94), 1.06), opacity: 0.55)
        }
        Task { withAnimation(.snappy(duration: 0.25)) { cue = .rest } }
        stepCount += 1
        hud = .symbol("square.grid.2x2", title: L10n.Localizable.List.Density.columns(new.columns))
    }

    // MARK: Reader

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

/// The wall's measures for one width of thumbnail. Every cell of a layout has one height, so
/// the row at the top follows from the offset alone.
nonisolated struct WallPreviewsLayout: Equatable {
    static let margin: CGFloat = 6
    static let columnSpacing: CGFloat = 5
    static let rowSpacing: CGFloat = 8
    static let numberSpacing: CGFloat = 3

    let columns: Int
    /// From the top of one row to the top of the next.
    let pitch: CGFloat

    /// Three columns, or five, on a phone and in the side pane; a wider wall keeps about the
    /// same two thumbnail widths with more columns.
    init(isDense: Bool, width: CGFloat, numberHeight: CGFloat) {
        // 86 and 134 pt give five and three on every phone, from 320 to 440 pt wide.
        let columns = isDense ? max(5, Int((width / 86).rounded())) : max(3, Int((width / 134).rounded()))
        self.columns = columns
        let inner = max(width - Self.margin * 2 - Self.columnSpacing * CGFloat(columns - 1), 0)
        let thumbnail = inner / CGFloat(columns) / Tokens.Aspect.preview
        pitch = thumbnail + Self.numberSpacing + numberHeight + Self.rowSpacing
    }
}

private final class WallPreviewsScroll {
    /// Where the scroll view is: its content offset, and the inset its top bar gives it.
    nonisolated struct Mark: Equatable {
        var offset: CGFloat = 0
        var inset: CGFloat = 0
        var bottomInset: CGFloat = 0
        var container: CGSize = .zero
        var contentHeight: CGFloat = 0
    }

    var mark = Mark()
    /// The wall has been brought to the page it opens at, or needed no bringing.
    var hasOpened = false
}

/// The wall as a whole for a moment after its thumbnails changed width.
nonisolated private struct WallPreviewsCue: Equatable {
    var scale: CGFloat
    var opacity: Double

    static let rest = WallPreviewsCue(scale: 1, opacity: 1)
}

private struct WallPreviewCell: View, Equatable {
    let index: Int
    let thumbnail: PreviewThumbnail?
    let failed: Bool
    /// The page last read: outlined in the tint.
    let isCurrent: Bool
    let numberHeight: CGFloat

    @Environment(\.look) private var look

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.index == rhs.index && lhs.thumbnail == rhs.thumbnail && lhs.failed == rhs.failed
            && lhs.isCurrent == rhs.isCurrent && lhs.numberHeight == rhs.numberHeight
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        VStack(spacing: WallPreviewsLayout.numberSpacing) {
            PreviewThumbnailView(thumbnail: thumbnail, failed: failed)
                .clipShape(shape)
                .overlay {
                    if isCurrent {
                        shape.strokeBorder(.tint, lineWidth: 3)
                    }
                }
            Text(index, format: .number)
                .font(.caption2.weight(isCurrent ? .bold : .regular))
                .monospacedDigit()
                .foregroundStyle(isCurrent ? look.label : look.secondaryLabel)
                .lineLimit(1)
                .frame(height: numberHeight)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.Localizable.Reader.Page.label(index))
        .accessibilityAddTraits(isCurrent ? [.isButton, .isSelected] : .isButton)
        .accessibilityHint(failed ? L10n.Localizable.ErrorView.Button.retry : "")
    }
}

/// Adds a pinch to the scroll view it is placed in: a `UIPinchGestureRecognizer` on the
/// `UIScrollView` itself. At that level the pinch and the scroll view's pan never run
/// together, so a pinch does not scroll and a two-finger scroll does not pinch. One step per
/// pinch: apart is 1, together is -1.
private struct WallPreviewsPinch: UIViewRepresentable {
    let onStep: (Int) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> Probe {
        let view = Probe()
        view.isUserInteractionEnabled = false
        view.coordinator = context.coordinator
        return view
    }

    func updateUIView(_ view: Probe, context: Context) {
        context.coordinator.onStep = onStep
    }

    static func dismantleUIView(_ view: Probe, coordinator: Coordinator) {
        coordinator.detach()
    }

    /// Finds the scroll view once it is in a window.
    final class Probe: UIView {
        weak var coordinator: Coordinator?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard window != nil else { return }
            var ancestor = superview
            while let view = ancestor, !(view is UIScrollView) {
                ancestor = view.superview
            }
            coordinator?.attach(to: ancestor as? UIScrollView)
        }
    }

    final class Coordinator: NSObject {
        var onStep: (Int) -> Void = { _ in }
        private let recognizer = UIPinchGestureRecognizer()
        private var hasStepped = false

        override init() {
            super.init()
            recognizer.addTarget(self, action: #selector(pinched))
        }

        func attach(to scrollView: UIScrollView?) {
            guard let scrollView, recognizer.view !== scrollView else { return }
            detach()
            scrollView.addGestureRecognizer(recognizer)
        }

        func detach() {
            recognizer.view?.removeGestureRecognizer(recognizer)
        }

        @objc private func pinched(_ recognizer: UIPinchGestureRecognizer) {
            switch recognizer.state {
            case .began:
                hasStepped = false
            case .changed where !hasStepped:
                if recognizer.scale >= 1.3 {
                    hasStepped = true
                    onStep(1)
                } else if recognizer.scale <= 0.77 {
                    hasStepped = true
                    onStep(-1)
                }
            default:
                break
            }
        }
    }
}
