import EhCore
import EhFeatures
import EhModels
import SwiftUI
import UIKit

/// Every comment in a plain list (`shelf.md` section 4, "Comments"): the uploader's first,
/// marked so. Swipe right to vote up, left to vote down; the long-press menu has the same, Edit
/// for one's own and Copy. The dock is one pill, "Write a comment". A comment a link pointed at
/// is scrolled to and highlighted.
struct ShelfCommentsScreen: View {
    @State private var model: CommentsModel

    @Environment(StackRouter.self) private var stack
    @Environment(AppRouter.self) private var appRouter: AppRouter?
    @Environment(\.look) private var look

    init(detail: GalleryDetailModel, scrollTo commentID: String?) {
        _model = State(initialValue: CommentsModel(detail: detail, scrollTo: commentID))
    }

    var body: some View {
        ScrollViewReader { proxy in
            List(Self.ordered(model.comments)) { item in
                ShelfCommentRow(item: item)
                    .equatable()
                    .opacity(item.id == model.highlightedCommentID ? model.highlightOpacity : 1)
                    .listRowBackground(look.background)
                    .listRowSeparatorTint(look.separator)
                    .swipeActions(edge: .leading) {
                        if item.comment.votable {
                            Button(L10n.Localizable.DetailView.ContextMenu.Button.voteUp, systemImage: "hand.thumbsup") {
                                model.vote(item, up: true)
                            }
                            .tint(.green)
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        if item.comment.votable {
                            Button(L10n.Localizable.DetailView.ContextMenu.Button.voteDown, systemImage: "hand.thumbsdown") {
                                model.vote(item, up: false)
                            }
                            .tint(.red)
                        }
                    }
                    .contextMenu { menu(for: item) }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(look.background)
            .animation(.default, value: model.highlightOpacity)
            .onChange(of: model.scrollTarget) { _, target in
                guard let target else { return }
                withAnimation { proxy.scrollTo(target, anchor: .top) }
            }
        }
        .environment(\.openURL, OpenURLAction { url in
            model.openLink(url, on: stack)
            return .handled
        })
        .task(id: model.isScrollTargetReady) { await model.scrollToTarget() }
        .navigationTitle(L10n.Localizable.CommentsView.Title.comments)
        .navigationBarTitleDisplayMode(.inline)
        .dock(.pill(writeComment)) { _ in
            if model.canCompose {
                model.compose()
            } else {
                appRouter?.presentSignIn()
            }
        }
        .sheet(item: $model.composer) { composer in
            PostCommentSheet(composer: composer) { text in model.submit(text, for: composer) }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: model.composer) { _, composer in composer != nil }
        .hud(linkHUD)
    }

    private var writeComment: DockItem {
        DockItem(
            title: L10n.Localizable.Gallery.Comments.write, systemImage: "square.and.pencil",
            action: .writeComment, isDimmed: !model.canCompose
        )
    }

    @ViewBuilder
    private func menu(for item: CommentItem) -> some View {
        if item.comment.votable {
            Button(L10n.Localizable.DetailView.ContextMenu.Button.voteUp, systemImage: "hand.thumbsup") {
                model.vote(item, up: true)
            }
            Button(L10n.Localizable.DetailView.ContextMenu.Button.voteDown, systemImage: "hand.thumbsdown") {
                model.vote(item, up: false)
            }
        }
        if item.comment.editable {
            Button(L10n.Localizable.PostCommentView.Title.editComment, systemImage: "square.and.pencil") {
                model.edit(item)
            }
        }
        Button(L10n.Localizable.ReadingView.ContextMenu.Button.copy, systemImage: "doc.on.doc") {
            UIPasteboard.general.string = item.comment.plainTextContent
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

    /// The uploader's comment first, the rest in the site's order.
    private static func ordered(_ comments: [CommentItem]) -> [CommentItem] {
        guard let index = comments.firstIndex(where: \.isUploaderComment), index > 0 else { return comments }
        var ordered = comments
        ordered.insert(ordered.remove(at: index), at: 0)
        return ordered
    }
}

/// One comment: the byline, then each block of its body. Links are `link` runs of the text, so
/// they take the tint and go through the screen's `openURL` action.
private struct ShelfCommentRow: View, Equatable {
    let item: CommentItem

    @Environment(\.look) private var look

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.item == rhs.item
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.small) {
            ShelfCommentByline(item: item)
            ForEach(item.blocks.indices, id: \.self) { index in
                switch item.blocks[index] {
                case .text(let text):
                    Text(text)
                        .font(.body)
                        .foregroundStyle(look.label)
                        .fixedSize(horizontal: false, vertical: true)
                case .images(let images):
                    ShelfCommentImages(images: images)
                }
            }
        }
        .padding(.vertical, Tokens.Spacing.small)
    }
}

/// One image at half the list's width, or two at a quarter each, optionally linked.
private struct ShelfCommentImages: View {
    let images: [CommentImage]

    @Environment(\.openURL) private var openURL

    var body: some View {
        HStack(spacing: 0) {
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
