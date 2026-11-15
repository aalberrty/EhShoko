import Dependencies
import EhCore
import EhFeatures
import EhModels
import SwiftUI

/// Every comment of the gallery, in Wall's terms (`wall.md` section 4): no title bar, only
/// the stack's floating Back; each comment a block with the author and the date above the
/// text and the score trailing; the uploader's own marked. Voting, editing and copying are
/// in a comment's context menu; writing one is the dock's pill.
struct WallCommentsView: View {
    @State private var model: CommentsModel
    @State private var hud: HUDConfiguration?

    @Environment(StackRouter.self) private var stack
    @Environment(AppRouter.self) private var appRouter: AppRouter?
    @Environment(\.look) private var look
    @Dependency(\.clipboardClient) private var clipboard

    init(detail: GalleryDetailModel, scrollTo commentID: String?) {
        _model = State(initialValue: CommentsModel(detail: detail, scrollTo: commentID))
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(model.comments) { item in
                        WallCommentBlock(item: item, isUploader: item.author == model.detail.uploader)
                            .equatable()
                            .opacity(item.id == model.highlightedCommentID ? model.highlightOpacity : 1)
                            .contextMenu { menu(for: item) }
                    }
                }
                .padding(.horizontal, 20)
            }
            .animation(.default, value: model.highlightOpacity)
            .onChange(of: model.scrollTarget) { _, target in
                guard let target else { return }
                withAnimation { proxy.scrollTo(target, anchor: .top) }
            }
        }
        .overlay {
            if model.comments.isEmpty {
                EmptyStateView(systemImage: "bubble.left.and.bubble.right")
            }
        }
        .background(look.background)
        .environment(\.openURL, OpenURLAction { url in
            model.openLink(url, on: stack)
            return .handled
        })
        .task(id: model.isScrollTargetReady) { await model.scrollToTarget() }
        // Named for VoiceOver and the Back menu, not drawn: the list starts under Back.
        .navigationTitle(L10n.Localizable.CommentsView.Title.comments)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(removing: .title)
        .dock(.pill(DockItem(
            title: L10n.Localizable.Gallery.Comments.write, systemImage: "square.and.pencil",
            action: .writeComment, isDimmed: !model.canCompose
        ))) { _ in
            if model.canCompose { model.compose() } else { appRouter?.presentSettings([.settings(.login)]) }
        }
        .sheet(item: $model.composer) { composer in
            PostCommentSheet(composer: composer) { text in model.submit(text, for: composer) }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: model.composer) { _, composer in composer != nil }
        .hud(linkHUD)
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
            clipboard.copyText(item.comment.plainTextContent)
            hud = .copiedToClipboard
        }
    }

    /// The copy HUD, or the progress of opening a linked gallery the app has not seen.
    private var linkHUD: Binding<HUDConfiguration?> {
        Binding(
            get: {
                switch model.linkState {
                case .resolving: .loading
                case .failed(let error): .error(caption: error.alertText)
                case nil: hud
                }
            },
            set: { newValue in
                guard newValue == nil else { return }
                hud = nil
                model.dismissLinkState()
            }
        )
    }
}

/// One comment: who and when, the score at the trailing edge, then each block of its body.
/// Links are `link` runs of the text, so they go through the screen's `openURL` action.
private struct WallCommentBlock: View, Equatable {
    let item: CommentItem
    let isUploader: Bool

    @Environment(\.look) private var look

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.item == rhs.item && lhs.isUploader == rhs.isUploader
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            ForEach(item.blocks.indices, id: \.self) { index in
                switch item.blocks[index] {
                case .text(let text):
                    Text(text)
                        .font(.subheadline)
                        .foregroundStyle(look.label)
                        .fixedSize(horizontal: false, vertical: true)
                case .images(let images):
                    WallCommentImages(images: images)
                }
            }
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(look.separator)
                .frame(height: 0.5)
        }
        .contentShape(.rect)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(verbatim: item.author)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(look.label)
            if isUploader {
                Text(L10n.Localizable.Gallery.Comments.uploader)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(look.secondaryLabel)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(look.fill3, in: .capsule)
            }
            Text(verbatim: item.comment.formattedDateString)
                .font(.caption)
                .foregroundStyle(look.secondaryLabel)
            Spacer(minLength: 8)
            if item.comment.votedUp {
                Image(systemName: "hand.thumbsup.fill")
                    .accessibilityLabel(L10n.Localizable.DetailView.ContextMenu.Button.voteUp)
            } else if item.comment.votedDown {
                Image(systemName: "hand.thumbsdown.fill")
                    .accessibilityLabel(L10n.Localizable.DetailView.ContextMenu.Button.voteDown)
            }
            if let score = item.comment.score {
                Text(verbatim: score)
                    .monospacedDigit()
            }
        }
        .font(.caption)
        .foregroundStyle(look.secondaryLabel)
        .lineLimit(1)
    }
}

/// One image at half the width, or two at a quarter each, optionally linked.
private struct WallCommentImages: View {
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
