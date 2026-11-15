import EhFeatures
import EhModels
import SwiftUI

/// "Comments" with "All 37 ›" over the first two comments (`shelf.md` section 4, item 8). A tap
/// on one opens the comments at it. Absent when the gallery has none: the dock's Comments
/// button still opens the list to write the first.
struct ShelfGalleryComments: View {
    let model: GalleryDetailModel

    var body: some View {
        let comments = model.comments
        if !comments.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                ShelfGallerySectionHeading(
                    title: L10n.Localizable.DetailView.Section.Title.comments,
                    link: L10n.Localizable.Gallery.all(comments.count)
                ) {
                    model.destination = .comments(scrollTo: nil)
                }
                ShelfCommentPreviews(comments: Array(comments.prefix(2))) { id in
                    model.destination = .comments(scrollTo: id)
                }
                .equatable()
                .padding(.top, Tokens.Spacing.small)
            }
        }
    }
}

private struct ShelfCommentPreviews: View, Equatable {
    let comments: [CommentItem]
    let open: (String) -> Void

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.comments == rhs.comments
    }

    var body: some View {
        VStack(spacing: Tokens.Spacing.small) {
            ForEach(comments) { item in
                Button {
                    open(item.id)
                } label: {
                    ShelfCommentPreview(item: item)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Tokens.Spacing.large)
    }
}

/// Author and date, the score trailing, then three lines of the text, on the look's surface.
private struct ShelfCommentPreview: View {
    let item: CommentItem

    @Environment(\.look) private var look

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.xSmall) {
            ShelfCommentByline(item: item)
            Text(item.summary)
                .font(.subheadline)
                .foregroundStyle(look.label)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, Tokens.Spacing.medium)
        .background(look.surface, in: .rect(cornerRadius: 16, style: .continuous))
        .contentShape(.rect(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// A comment's author (semibold) and date on one line, "Uploader" on the uploader's, and the
/// score trailing in monospaced digits. Shared by the page's previews and the comments list.
struct ShelfCommentByline: View {
    let item: CommentItem

    @Environment(\.look) private var look

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Tokens.Spacing.small) {
            Text(item.author)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(look.label)
                .layoutPriority(1)
            if Self.isUploader(item) {
                Text(L10n.Localizable.Gallery.Comments.uploader)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tint)
            }
            Text(item.comment.formattedDateString)
                .font(.footnote)
                .foregroundStyle(look.secondaryLabel)
            Spacer(minLength: Tokens.Spacing.small)
            if item.comment.votedUp || item.comment.votedDown {
                Image(systemName: item.comment.votedUp ? "hand.thumbsup.fill" : "hand.thumbsdown.fill")
                    .font(.caption)
                    .foregroundStyle(.tint)
                    .accessibilityLabel(
                        item.comment.votedUp
                            ? L10n.Localizable.DetailView.ContextMenu.Button.voteUp
                            : L10n.Localizable.DetailView.ContextMenu.Button.voteDown
                    )
            }
            if let score = item.comment.score {
                Text(score)
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(look.secondaryLabel)
            }
        }
        .lineLimit(1)
    }

    /// The site gives the uploader's comment the id 0 and no score.
    static func isUploader(_ item: CommentItem) -> Bool {
        item.comment.commentID == "0"
    }
}
