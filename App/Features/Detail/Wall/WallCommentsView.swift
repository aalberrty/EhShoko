import Dependencies
import EhCore
import EhFeatures
import EhModels
import SwiftUI

private typealias MenuTitles = L10n.Localizable.DetailView.ContextMenu.Button

/// Wall's Comments (`wall.md` section 4, "Child screens"): no title in the top bar, only the
/// system's Back floating over the blocks. The uploader's comment comes first; each comment is
/// a block with its author and date above the text and its score trailing. Voting, Edit for
/// one's own and Copy are in the long-press menu; the dock is one pill, "Write a comment". A
/// comment a link pointed at is scrolled to and highlighted, as in v3.
struct WallCommentsView: View {
    @State private var model: CommentsModel
    @State private var asksToSignIn = false
    @State private var copyHUD: HUDConfiguration?

    @Environment(StackRouter.self) private var stack
    @Environment(AppRouter.self) private var appRouter: AppRouter?
    @Environment(\.chrome) private var chrome
    @Environment(\.look) private var look
    @Dependency(\.clipboardClient) private var clipboard

    init(detail: GalleryDetailModel, scrollTo commentID: String?) {
        _model = State(initialValue: CommentsModel(detail: detail, scrollTo: commentID))
    }

    var body: some View {
        let metrics = WallGalleryMetrics(isPane: chrome.isSidePane, isShort: false)
        let comments = Self.ordered(model.comments)
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Tokens.Spacing.small) {
                    heading(count: comments.count)
                    ForEach(comments) { item in
                        WallCommentBlock(item: item, fill: metrics.fill(look))
                            .equatable()
                            .opacity(item.id == model.highlightedCommentID ? model.highlightOpacity : 1)
                            .contextMenu { menu(for: item) }
                    }
                }
                .padding(.horizontal, Tokens.Spacing.medium)
                .padding(.bottom, Tokens.Spacing.large)
            }
            .animation(.default, value: model.highlightOpacity)
            .onChange(of: model.scrollTarget) { _, target in
                guard let target else { return }
                withAnimation { proxy.scrollTo(target, anchor: .top) }
            }
        }
        .background { metrics.ground(look).ignoresSafeArea() }
        // The title names the screen for VoiceOver and the Back menu; the bar does not draw it.
        .navigationTitle(L10n.Localizable.CommentsView.Title.comments)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(removing: .title)
        .environment(\.openURL, OpenURLAction { url in
            model.openLink(url, on: stack)
            return .handled
        })
        .task(id: model.isScrollTargetReady) { await model.scrollToTarget() }
        .dock(.pill(DockItem(
            title: L10n.Localizable.Gallery.Comments.write, systemImage: "square.and.pencil",
            action: .writeComment, isDimmed: !model.canCompose
        ))) { _ in
            model.canCompose ? model.compose() : (asksToSignIn = true)
        }
        // The composer belongs to this screen's model, which also edits.
        .sheet(item: $model.composer) { composer in
            PostCommentSheet(composer: composer) { text in model.submit(text, for: composer) }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: model.composer) { _, composer in composer != nil }
        .hud(linkHUD)
        .hud($copyHUD)
        .alert(L10n.Localizable.ErrorView.Headline.loginRequired, isPresented: $asksToSignIn) {
            Button(L10n.Localizable.NotLoginView.Button.login) {
                appRouter?.presentSettings([.settings(.account), .settings(.login)])
            }
            AlertCancelButton(title: L10n.Localizable.JumpPageView.Button.cancel)
        } message: {
            Text(L10n.Localizable.List.Signin.note)
        }
    }

    /// "COMMENTS" and how many there are, where the bar's title would have been.
    private func heading(count: Int) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(L10n.Localizable.CommentsView.Title.comments)
                .lookSectionHeader()
            Spacer(minLength: Tokens.Spacing.small)
            Text(count, format: .number)
                .font(.footnote.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(look.secondaryLabel)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, Tokens.Spacing.small)
        .padding(.top, Tokens.Spacing.small)
        .padding(.bottom, Tokens.Spacing.xSmall)
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

    /// The uploader's comment first, the rest in the site's order.
    private static func ordered(_ comments: [CommentItem]) -> [CommentItem] {
        guard let index = comments.firstIndex(where: WallCommentBlock.isUploader), index > 0 else { return comments }
        var ordered = comments
        ordered.insert(ordered.remove(at: index), at: 0)
        return ordered
    }
}

/// One comment as a block on a fill: the author and date, the score trailing, then each block
/// of its body. Links are `link` runs of the text, so they take the tint and go through the
/// screen's `openURL` action.
private struct WallCommentBlock: View, Equatable {
    let item: CommentItem
    let fill: Color

    @Environment(\.look) private var look
    @Environment(\.dynamicTypeSize) private var typeSize

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.item == rhs.item && lhs.fill == rhs.fill
    }

    /// The site gives the uploader's comment the id 0 and no score.
    static func isUploader(_ item: CommentItem) -> Bool {
        item.comment.commentID == "0"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.small) {
            byline
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
        .padding(.horizontal, 14)
        .padding(.vertical, Tokens.Spacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(fill, in: .rect(cornerRadius: 18, style: .continuous))
        .contentShape(.contextMenuPreview, .rect(cornerRadius: 18, style: .continuous))
    }

    private var byline: some View {
        // At the accessibility text sizes each part takes a line of its own.
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: Tokens.Spacing.small))
        return layout {
            Text(item.author)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(look.label)
            if Self.isUploader(item) {
                Text(L10n.Localizable.Gallery.Comments.uploader)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tint)
            }
            // A long name gives way to the date and the score, not the other way round.
            Text(item.comment.formattedDateString)
                .font(.caption)
                .foregroundStyle(look.secondaryLabel)
                .layoutPriority(1)
            if !typeSize.isAccessibilitySize {
                Spacer(minLength: Tokens.Spacing.small)
            }
            if item.comment.votedUp || item.comment.votedDown {
                Image(systemName: item.comment.votedUp ? "hand.thumbsup.fill" : "hand.thumbsdown.fill")
                    .font(.caption)
                    .foregroundStyle(.tint)
                    .accessibilityLabel(item.comment.votedUp ? MenuTitles.voteUp : MenuTitles.voteDown)
            }
            if let score = item.comment.score {
                Text(score)
                    .font(.footnote.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(look.secondaryLabel)
                    .layoutPriority(2)
            }
        }
        .lineLimit(1)
    }
}

/// One image at half the block's width, or two at a quarter each, optionally linked.
private struct WallCommentImages: View {
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
