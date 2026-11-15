import EhFeatures
import EhModels
import SwiftUI

private typealias MenuTitles = L10n.Localizable.DetailView.ContextMenu.Button

/// Tag detail (`wall.md` section 4, "Child screens"): a sheet at the medium height with the
/// tag's namespace beside its dot, its translated name, the description and images, then what
/// can be done with it as pills: search the tag and, signed in, vote on it. The translation's
/// links follow. The sheet is the system's; what is on it is fills, never glass.
struct WallTagDetailSheet: View {
    let detail: TagDetail
    let model: GalleryDetailModel

    @Environment(StackRouter.self) private var stack: StackRouter?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.look) private var look

    var body: some View {
        let tag = self.tag
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Tokens.Spacing.large) {
                    header(namespace: tag?.namespace)
                    if !detail.imageURLs.isEmpty {
                        images
                    }
                    if let chip = tag?.chip {
                        actions(chip)
                    }
                    if !detail.links.isEmpty {
                        links
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, Tokens.Spacing.xLarge)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    SheetCloseButton { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    /// The tag the sheet is about: the one on the page whose translation this is.
    private var tag: (chip: DetailTagChip, namespace: TagNamespace?)? {
        for row in model.tagRows {
            if let chip = row.chips.first(where: { $0.detail == detail }) {
                return (chip, row.tag.namespace)
            }
        }
        return nil
    }

    private func header(namespace: TagNamespace?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let namespace {
                HStack(spacing: 6) {
                    Circle()
                        .fill(namespace.markColor)
                        .frame(width: 7, height: 7)
                    Text(namespace.localizedName)
                        .lookSectionHeader()
                }
            }
            Text(detail.title.removingEmojiPresentation)
                .font(.title2.bold())
                .lookTitleDesign()
                .foregroundStyle(look.label)
                .accessibilityAddTraits(.isHeader)
            if !detail.description.isEmpty {
                Text(detail.description)
                    .font(.subheadline)
                    .foregroundStyle(look.secondaryLabel)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var images: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: Tokens.Spacing.small) {
                ForEach(detail.imageURLs, id: \.self) { url in
                    RemoteImage(url: url, size: CGSize(width: 110, height: 110 / Tokens.Aspect.preview), cornerRadius: 6)
                }
            }
        }
        .scrollIndicators(.hidden)
        .contentMargins(.horizontal, 20, for: .scrollContent)
        .frame(height: 110 / Tokens.Aspect.preview)
        .padding(.horizontal, -20)
    }

    private func actions(_ chip: DetailTagChip) -> some View {
        FlowLayout(spacing: Tokens.Spacing.small) {
            pill(L10n.Localizable.SearchView.Title.search, systemImage: "magnifyingglass") {
                dismiss()
                stack?.push(.search(keyword: chip.searchKeyword))
            }
            if model.isLoggedIn {
                if chip.hasVote {
                    pill(
                        MenuTitles.withdrawVote,
                        systemImage: chip.content.isVotedUp ? "hand.thumbsup.fill" : "hand.thumbsdown.fill"
                    ) {
                        model.voteTag(chip, vote: chip.withdrawVote)
                    }
                } else {
                    pill(MenuTitles.voteUp, systemImage: "hand.thumbsup") { model.voteTag(chip, vote: 1) }
                    pill(MenuTitles.voteDown, systemImage: "hand.thumbsdown") { model.voteTag(chip, vote: -1) }
                }
            }
        }
    }

    private func pill(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(look.label)
                .lineLimit(1)
                .padding(.horizontal, 14)
                .frame(minHeight: 38)
                .background(look.fill2, in: .capsule)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
    }

    private var links: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.small) {
            Text(L10n.Localizable.TagDetailView.Section.Title.links)
                .lookSectionHeader()
            ForEach(detail.links, id: \.self) { url in
                Link(destination: url) {
                    Label(url.absoluteString, systemImage: "link")
                        .font(.footnote)
                        .foregroundStyle(look.label)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }
        }
    }
}
