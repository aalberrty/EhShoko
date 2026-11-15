import EhCore
import EhFeatures
import EhModels
import Kingfisher
import SwiftUI

private typealias MenuTitles = L10n.Localizable.DetailView.ContextMenu.Button

/// "TAGS" with "All 58 ›" over the tags as one wrapping run of chips (`wall.md` section 4,
/// item 5): each chip 28 high on a fill with a dot in its namespace's colour. The first eleven
/// are shown, then "+47", which shows the rest in place, as "All 58 ›" does. A tap searches
/// the tag; a long press offers the tag's details and, signed in, the votes.
struct WallGalleryTags: View {
    let model: GalleryDetailModel
    let metrics: WallGalleryMetrics
    let search: (String) -> Void

    @Environment(SettingsStore.self) private var settings
    @State private var isExpanded = false

    static let visibleChips = 11

    var body: some View {
        let rows = model.tagRows
        if !rows.isEmpty {
            let total = rows.reduce(0) { $0 + $1.chips.count }
            let hidden = isExpanded ? 0 : max(total - Self.visibleChips, 0)
            VStack(alignment: .leading, spacing: 9) {
                WallGallerySectionHeading(
                    title: L10n.Localizable.Gallery.tags,
                    link: hidden > 0 ? L10n.Localizable.Gallery.all(total) : nil,
                    action: expand
                )
                WallTagCloud(
                    tags: tags(in: rows, count: total - hidden), hidden: hidden,
                    style: WallTagCloud.Style(
                        fillsFaintly: metrics.isPane, offersDetail: settings.translatesTags, isLoggedIn: model.isLoggedIn
                    ),
                    actions: WallTagActions(
                        search: search,
                        vote: { chip, vote in model.voteTag(chip, vote: vote) },
                        showDetail: { detail in model.showTagDetail(detail) },
                        expand: expand
                    )
                )
                .equatable()
            }
        }
    }

    private func expand() {
        withAnimation(.snappy) { isExpanded = true }
    }

    /// The first `count` tags in the site's order, namespace by namespace, each with the text
    /// it shows. The texts are looked up here, so the cloud is drawn again only when one of
    /// them changes.
    private func tags(in rows: [DetailTagRow], count: Int) -> [WallTag] {
        let translates = settings.translatesTags
        let showsImages = settings.showsImagesInTags
        var tags: [WallTag] = []
        tags.reserveCapacity(count)
        for row in rows {
            for chip in row.chips {
                guard tags.count < count else { return tags }
                let translation = translates ? model.translation(for: chip) : nil
                tags.append(WallTag(
                    chip: chip, namespace: row.tag.namespace,
                    text: translates
                        ? chip.content.chipText(translation: translation, showsImages: showsImages) : chip.content.text,
                    imageURL: showsImages ? translation?.valueImageURL : nil
                ))
            }
        }
        return tags
    }
}

/// One tag of the cloud.
nonisolated struct WallTag: Identifiable, Equatable {
    let chip: DetailTagChip
    let namespace: TagNamespace?
    let text: String
    let imageURL: URL?

    var id: String { chip.id }
}

struct WallTagActions {
    let search: (String) -> Void
    let vote: (DetailTagChip, Int) -> Void
    let showDetail: (TagDetail) -> Void
    let expand: () -> Void
}

private struct WallTagCloud: View, Equatable {
    nonisolated struct Style: Equatable {
        /// On the pane's surface the chips take the look's faintest fill.
        let fillsFaintly: Bool
        /// v3 offered a tag's details only while translating.
        let offersDetail: Bool
        let isLoggedIn: Bool
    }

    let tags: [WallTag]
    /// How many more there are: the "+47" chip.
    let hidden: Int
    let style: Style
    let actions: WallTagActions

    @Environment(\.look) private var look

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.tags == rhs.tags && lhs.hidden == rhs.hidden && lhs.style == rhs.style
    }

    var body: some View {
        let fill = style.fillsFaintly ? look.fill3 : look.surface
        FlowLayout(spacing: 6) {
            ForEach(tags) { tag in
                Button {
                    actions.search(tag.chip.searchKeyword)
                } label: {
                    WallTagChip(tag: tag, fill: fill)
                }
                .buttonStyle(.plain)
                .contextMenu { menu(for: tag.chip) }
            }
            if hidden > 0 {
                Button(action: actions.expand) {
                    Text(L10n.Localizable.Gallery.Tags.more(hidden))
                        .font(.footnote)
                        .monospacedDigit()
                        .foregroundStyle(look.secondaryLabel)
                        .padding(.horizontal, 11)
                        .frame(minHeight: 28)
                        .background(fill, in: .capsule)
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func menu(for chip: DetailTagChip) -> some View {
        if style.offersDetail, let detail = chip.detail {
            Button(MenuTitles.detail, systemImage: "doc.richtext") {
                actions.showDetail(detail)
            }
        }
        if style.isLoggedIn {
            if chip.hasVote {
                Button(
                    MenuTitles.withdrawVote,
                    systemImage: chip.content.isVotedUp ? "hand.thumbsup.fill" : "hand.thumbsdown.fill"
                ) {
                    actions.vote(chip, chip.withdrawVote)
                }
            } else {
                Button(MenuTitles.voteUp, systemImage: "hand.thumbsup") { actions.vote(chip, 1) }
                Button(MenuTitles.voteDown, systemImage: "hand.thumbsdown") { actions.vote(chip, -1) }
            }
        }
    }
}

/// A tag in a capsule: the namespace's dot, a mark when the user voted on it, the text.
private struct WallTagChip: View {
    let tag: WallTag
    let fill: Color

    @Environment(\.look) private var look
    @ScaledMetric(relativeTo: .footnote) private var dot: CGFloat = 7

    var body: some View {
        let content = tag.chip.content
        HStack(spacing: 6) {
            Circle()
                .fill((tag.namespace ?? .other).markColor)
                .frame(width: dot, height: dot)
            if content.isVotedUp || content.isVotedDown {
                Image(systemName: content.isVotedUp ? "hand.thumbsup.fill" : "hand.thumbsdown.fill")
                    .imageScale(.small)
                    .foregroundStyle(.tint)
            }
            Text(tag.text)
                .foregroundStyle(content.textColor ?? (content.isWeak ? look.secondaryLabel : look.label))
            if let imageURL = tag.imageURL {
                // Sized by an invisible symbol, so it follows the text size.
                Image(systemName: "photo")
                    .hidden()
                    .overlay { WallTagImage(url: imageURL) }
                    .accessibilityHidden(true)
            }
        }
        .font(.footnote)
        .lineLimit(1)
        .padding(.leading, 9)
        .padding(.trailing, 11)
        .frame(minHeight: 28)
        // A watched tag keeps the colour the site gives it.
        .background(content.backgroundColor?.color ?? fill, in: .capsule)
        .contentShape(.capsule)
        .accessibilityElement(children: .combine)
    }
}

/// A translation's image beside its tag, decoded no larger than 48 pt.
private struct WallTagImage: View {
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
