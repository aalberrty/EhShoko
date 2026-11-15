import Dependencies
import EhCore
import EhFeatures
import EhModels
import SwiftUI

private typealias MenuTitles = L10n.Localizable.DetailView.ContextMenu.Button

/// Ledger's Comments (`ledger.md` section 4, child screens): a plain list with hairlines, the
/// uploader's comment first under its heading. Each comment has its author and date in small
/// capitals with the score trailing, then its text. Swipe right to vote up, left to vote down;
/// the long-press menu has the same, Edit for one's own and Copy. The dock is one pill, "Write
/// a comment". A comment linked from outside is scrolled to and highlighted, as in v3.
struct LedgerCommentsView: View {
    @State private var model: CommentsModel
    @State private var copyHUD: HUDConfiguration?

    @Environment(StackRouter.self) private var stack
    @Environment(AppRouter.self) private var appRouter: AppRouter?
    @Environment(\.look) private var look
    @Dependency(\.clipboardClient) private var clipboard

    init(detail: GalleryDetailModel, scrollTo commentID: String?) {
        _model = State(initialValue: CommentsModel(detail: detail, scrollTo: commentID))
    }

    var body: some View {
        let comments = model.comments
        let uploader = comments.first(where: \.isUploaderComment)
        let others = comments.filter { !$0.isUploaderComment }
        ScrollViewReader { proxy in
            List {
                if let uploader {
                    Section {
                        row(uploader)
                    } header: {
                        heading(L10n.Localizable.Gallery.Comments.uploader)
                    }
                }
                Section {
                    ForEach(others) { row($0) }
                } header: {
                    if uploader != nil, !others.isEmpty {
                        heading(L10n.Localizable.CommentsView.Title.comments)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .animation(.default, value: model.highlightOpacity)
            .onChange(of: model.scrollTarget) { _, target in
                guard let target else { return }
                withAnimation { proxy.scrollTo(target, anchor: .top) }
            }
        }
        .background { look.background.ignoresSafeArea() }
        .navigationTitle(L10n.Localizable.CommentsView.Title.comments)
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.openURL, OpenURLAction { url in
            model.openLink(url, on: stack)
            return .handled
        })
        .task(id: model.isScrollTargetReady) { await model.scrollToTarget() }
        .dock(.pill(DockItem(
            title: L10n.Localizable.Gallery.Comments.write, action: .writeComment, isDimmed: !model.canCompose
        ))) { _ in
            if model.canCompose {
                model.compose()
            } else {
                appRouter?.presentSettings([.settings(.account), .settings(.login)])
            }
        }
        // The composer belongs to this screen's model, which also edits.
        .sheet(item: $model.composer) { composer in
            PostCommentSheet(composer: composer) { text in model.submit(text, for: composer) }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: model.composer) { _, composer in composer != nil }
        .hud(linkHUD)
        .hud($copyHUD)
    }

    private func heading(_ title: String) -> some View {
        Text(title)
            .ledgerSmallCaps()
    }

    private func row(_ item: CommentItem) -> some View {
        LedgerCommentRow(item: item)
            .equatable()
            .opacity(item.id == model.highlightedCommentID ? model.highlightOpacity : 1)
            .listRowBackground(Color.clear)
            .listRowSeparatorTint(look.separator)
            .swipeActions(edge: .leading) {
                if item.comment.votable {
                    Button {
                        model.vote(item, up: true)
                    } label: {
                        Label(L10n.Localizable.DetailView.ContextMenu.Button.voteUp, systemImage: "hand.thumbsup")
                    }
                    .tint(.green)
                }
            }
            .swipeActions(edge: .trailing) {
                if item.comment.votable {
                    Button {
                        model.vote(item, up: false)
                    } label: {
                        Label(L10n.Localizable.DetailView.ContextMenu.Button.voteDown, systemImage: "hand.thumbsdown")
                    }
                    .tint(.red)
                }
            }
            .contextMenu { menu(for: item) }
    }

    @ViewBuilder
    private func menu(for item: CommentItem) -> some View {
        if item.comment.votable {
            Button(MenuTitles.voteUp, systemImage: "hand.thumbsup") { model.vote(item, up: true) }
            Button(MenuTitles.voteDown, systemImage: "hand.thumbsdown") { model.vote(item, up: false) }
        }
        if item.comment.editable {
            Button(L10n.Localizable.PostCommentView.Title.editComment, systemImage: "square.and.pencil") {
                model.edit(item)
            }
        }
        Button(L10n.Localizable.ReadingView.ContextMenu.Button.copy, systemImage: "doc.on.doc") {
            clipboard.copyText(item.comment.plainTextContent)
            copyHUD = .copiedToClipboard
        }
    }

    private var linkHUD: Binding<HUDConfiguration?> {
        Binding(
            get: {
                switch model.linkState {
                case .resolving: .loading
                case .failed(let error): .error(caption: error.alertText)
                case nil: nil
                }
            },
            set: { if $0 == nil { model.dismissLinkState() } }
        )
    }
}

/// One comment: author and date in small capitals, the score trailing in monospaced digits,
/// then each block of the body, its links as `link` runs that go through the screen's
/// `openURL`.
private struct LedgerCommentRow: View, Equatable {
    let item: CommentItem

    @Environment(\.look) private var look

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.item == rhs.item
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(item.author) · \(item.comment.formattedDateString)")
                    .ledgerSmallCaps()
                    .lineLimit(1)
                Spacer(minLength: 8)
                if item.comment.votedUp || item.comment.votedDown {
                    Image(systemName: item.comment.votedUp ? "hand.thumbsup.fill" : "hand.thumbsdown.fill")
                        .font(.caption2)
                        .foregroundStyle(.tint)
                        .accessibilityLabel(
                            item.comment.votedUp
                                ? L10n.Localizable.DetailView.ContextMenu.Button.voteUp
                                : L10n.Localizable.DetailView.ContextMenu.Button.voteDown
                        )
                }
                if let score = item.comment.score {
                    Text(score)
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(look.secondaryLabel)
                }
            }
            ForEach(item.blocks.indices, id: \.self) { index in
                switch item.blocks[index] {
                case .text(let text):
                    Text(text)
                        .font(.subheadline)
                        .lineSpacing(2)
                        .foregroundStyle(look.label)
                        .fixedSize(horizontal: false, vertical: true)
                case .images(let images):
                    LedgerCommentImages(images: images)
                }
            }
        }
        .padding(.vertical, 6)
    }
}

/// One image at half the row's width, or two at a quarter each, optionally linked.
private struct LedgerCommentImages: View {
    let images: [CommentImage]

    @Environment(\.openURL) private var openURL

    var body: some View {
        HStack(spacing: 6) {
            ForEach(images.indices, id: \.self) { index in
                let image = images[index]
                let fraction: CGFloat = images.count > 1 ? 4 : 2
                RemoteImage(url: image.imageURL, width: 600 / fraction)
                    .containerRelativeFrame(.horizontal) { width, _ in width / fraction }
                    .onTapGesture {
                        if let link = image.link { openURL(link) }
                    }
                    .accessibilityAddTraits(image.link == nil ? [] : .isLink)
            }
        }
    }
}
