import EhCore
import EhDatabase
import EhFeatures
import EhModels
import Kingfisher
import SwiftUI

/// "Tags" with "All 58 ›" over one line per namespace (`shelf.md` section 4, item 7): the
/// namespace's name right-aligned in a 60 pt column, then its tags as chips. A group with more
/// than six shows six and "+12", which shows the rest; "All 58 ›" opens every group. A tap
/// searches the tag; a long press offers v3's menu (the tag's details, vote up, vote down).
struct ShelfGalleryTags: View {
    let model: GalleryDetailModel

    @Environment(SettingsStore.self) private var settings
    @Environment(StackRouter.self) private var stack: StackRouter?
    @State private var expanded: Set<String> = []
    @State private var expandsAll = false
    @State private var searchCount = 0

    static let visibleChips = 6

    var body: some View {
        let rows = model.tagRows
        if !rows.isEmpty {
            let total = rows.reduce(0) { $0 + $1.chips.count }
            let hasHidden = rows.contains { $0.chips.count > Self.visibleChips && !isExpanded($0) }
            VStack(alignment: .leading, spacing: 0) {
                ShelfGallerySectionHeading(
                    title: L10n.Localizable.Gallery.tags,
                    link: hasHidden ? L10n.Localizable.Gallery.all(total) : nil
                ) {
                    withAnimation(.snappy) { expandsAll = true }
                }
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(rows) { row in
                        ShelfTagGroup(
                            row: row, isExpanded: isExpanded(row),
                            style: style(for: row), actions: actions
                        )
                        .equatable()
                    }
                }
                .padding(.top, 4)
            }
            .sensoryFeedback(.impact(flexibility: .soft), trigger: searchCount)
        }
    }

    private func isExpanded(_ row: DetailTagRow) -> Bool {
        expandsAll || expanded.contains(row.id)
    }

    /// The chips' texts, looked up here so that a group redraws only when its own change.
    private func style(for row: DetailTagRow) -> ShelfTagGroup.Style {
        let translates = settings.translatesTags
        let showsImages = settings.showsImagesInTags
        var chips: [String: ShelfTagGroup.ChipText] = [:]
        if translates {
            for chip in row.chips {
                let translation = model.translation(for: chip)
                chips[chip.id] = ShelfTagGroup.ChipText(
                    text: chip.content.chipText(translation: translation, showsImages: showsImages),
                    imageURL: showsImages ? translation?.valueImageURL : nil
                )
            }
        }
        return ShelfTagGroup.Style(
            chips: chips, offersDetail: translates, isLoggedIn: model.isLoggedIn
        )
    }

    private var actions: ShelfTagActions {
        ShelfTagActions(
            search: { keyword in
                searchCount += 1
                stack?.push(.search(keyword: keyword))
            },
            vote: { chip, vote in model.voteTag(chip, vote: vote) },
            showDetail: { detail in model.showTagDetail(detail) },
            expand: { id in
                withAnimation(.snappy) { _ = expanded.insert(id) }
            }
        )
    }
}

struct ShelfTagActions {
    let search: (String) -> Void
    let vote: (DetailTagChip, Int) -> Void
    let showDetail: (TagDetail) -> Void
    let expand: (String) -> Void
}

/// One namespace: its name and its chips.
private struct ShelfTagGroup: View, Equatable {
    struct ChipText: Equatable {
        let text: String
        let imageURL: URL?
    }

    struct Style: Equatable {
        /// Translated texts by chip id; empty when tags are not translated.
        let chips: [String: ChipText]
        /// v3 offered a tag's details only while translating.
        let offersDetail: Bool
        let isLoggedIn: Bool
    }

    let row: DetailTagRow
    let isExpanded: Bool
    let style: Style
    let actions: ShelfTagActions

    @Environment(\.look) private var look

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.row == rhs.row && lhs.isExpanded == rhs.isExpanded && lhs.style == rhs.style
    }

    var body: some View {
        let hidden = isExpanded ? 0 : max(row.chips.count - ShelfGalleryTags.visibleChips, 0)
        HStack(alignment: .top, spacing: 10) {
            // As tall as a chip, so the name sits level with the first line of chips.
            Text(row.tag.namespace?.localizedName ?? row.tag.rawNamespace)
                .font(.caption)
                .foregroundStyle(look.secondaryLabel)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: 60, alignment: .trailing)
                .frame(minHeight: 28)
                .accessibilityAddTraits(.isHeader)
            FlowLayout(spacing: 6) {
                ForEach(row.chips.prefix(row.chips.count - hidden)) { chip in
                    chipButton(chip)
                }
                if hidden > 0 {
                    Button {
                        actions.expand(row.id)
                    } label: {
                        Text(L10n.Localizable.Gallery.Tags.more(hidden))
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.tint)
                            .padding(.horizontal, 4)
                            .frame(minHeight: 28)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, ShelfGalleryLayout.leading)
        .padding(.trailing, ShelfGalleryLayout.trailing)
        .padding(.vertical, 5)
    }

    private func chipButton(_ chip: DetailTagChip) -> some View {
        let text = style.chips[chip.id]
        return Button {
            actions.search(chip.searchKeyword)
        } label: {
            ShelfTagChip(text: text?.text ?? chip.content.text, imageURL: text?.imageURL, content: chip.content)
        }
        .buttonStyle(.plain)
        .contextMenu { menu(for: chip) }
    }

    @ViewBuilder
    private func menu(for chip: DetailTagChip) -> some View {
        if style.offersDetail, let detail = chip.detail {
            Button(L10n.Localizable.DetailView.ContextMenu.Button.detail, systemImage: "doc.richtext") {
                actions.showDetail(detail)
            }
        }
        if style.isLoggedIn {
            if chip.hasVote {
                Button(
                    L10n.Localizable.DetailView.ContextMenu.Button.withdrawVote,
                    systemImage: chip.content.isVotedUp ? "hand.thumbsup.fill" : "hand.thumbsdown.fill"
                ) {
                    actions.vote(chip, chip.withdrawVote)
                }
            } else {
                Button(L10n.Localizable.DetailView.ContextMenu.Button.voteUp, systemImage: "hand.thumbsup") {
                    actions.vote(chip, 1)
                }
                Button(L10n.Localizable.DetailView.ContextMenu.Button.voteDown, systemImage: "hand.thumbsdown") {
                    actions.vote(chip, -1)
                }
            }
        }
    }
}

/// A tag in a capsule 28 high on the look's faintest fill; one the user voted for is marked.
private struct ShelfTagChip: View {
    let text: String
    let imageURL: URL?
    let content: GalleryTag.Content

    @Environment(\.look) private var look

    var body: some View {
        HStack(spacing: Tokens.Spacing.xSmall) {
            if content.isVotedUp || content.isVotedDown {
                Image(systemName: content.isVotedUp ? "hand.thumbsup.fill" : "hand.thumbsdown.fill")
                    .imageScale(.small)
                    .foregroundStyle(.tint)
            }
            Text(text)
                .foregroundStyle(foreground)
            if let imageURL {
                // Sized by an invisible symbol, so it follows the text size.
                Image(systemName: "photo")
                    .hidden()
                    .overlay { ShelfTagImage(url: imageURL) }
                    .accessibilityHidden(true)
            }
        }
        .font(.footnote)
        .lineLimit(1)
        .padding(.horizontal, 11)
        .frame(minHeight: 28)
        .background(background, in: .capsule)
        .contentShape(.capsule)
        .accessibilityElement(children: .combine)
    }

    /// A watched tag keeps the colour the site gives it.
    private var background: Color {
        content.backgroundColor?.color ?? look.fill3
    }

    private var foreground: Color {
        content.textColor ?? (content.isWeak ? look.secondaryLabel : look.label)
    }
}

/// A translation's image beside its tag, decoded no larger than 48 pt.
private struct ShelfTagImage: View {
    let url: URL

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        KFImage(url)
            .setProcessor(DownsampleProcessor(
                pixelSize: CGSize(width: 48 * displayScale, height: 48 * displayScale), mode: .fit
            ))
            .cacheOriginalImage()
            .cacheMemoryOnly()
            .scaleFactor(displayScale)
            .cancelOnDisappear(true)
            .resizable()
            .aspectRatio(contentMode: .fit)
    }
}
