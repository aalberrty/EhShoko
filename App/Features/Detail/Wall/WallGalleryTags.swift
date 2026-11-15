import EhCore
import EhDatabase
import EhFeatures
import EhModels
import SwiftUI

/// The gallery's tags as one wrapping run of chips, each with a dot in its namespace's hue:
/// the first few, then "+47", which shows the rest in place, as "All 58" does.
///
/// A tap searches the tag; a long press gives the tag's menu (its translation's detail, and
/// votes with an account). Translations and tag images follow the existing settings.
struct WallGalleryTags: View {
    let model: GalleryDetailModel
    let metrics: WallGalleryMetrics

    @Environment(SettingsStore.self) private var settings
    @Environment(StackRouter.self) private var stack: StackRouter?
    @Environment(\.look) private var look
    @State private var isExpanded = false
    @State private var searchCount = 0

    var body: some View {
        let rows = model.tagRows
        if !rows.isEmpty {
            let total = rows.reduce(0) { $0 + $1.chips.count }
            let hidden = isExpanded ? 0 : max(total - metrics.tagLimit, 0)
            VStack(alignment: .leading, spacing: 9) {
                WallSectionHeader(
                    title: L10n.Localizable.Gallery.tags,
                    link: total > metrics.tagLimit ? L10n.Localizable.Gallery.all(total) : nil
                ) {
                    withAnimation(.snappy) { isExpanded.toggle() }
                }
                WallTagChips(
                    items: items(of: rows, limit: total - hidden), hidden: hidden,
                    fill: metrics.fill(in: look), translates: settings.translatesTags,
                    isLoggedIn: model.isLoggedIn, actions: actions
                )
                .equatable()
            }
            .sensoryFeedback(.impact(flexibility: .soft), trigger: searchCount)
        }
    }

    /// The first `limit` tags in the page's order, with the text each chip shows. Only these
    /// are looked up in the translations, which reading observes.
    private func items(of rows: [DetailTagRow], limit: Int) -> [WallTagItem] {
        let translates = settings.translatesTags
        let showsImages = settings.showsImagesInTags
        var items: [WallTagItem] = []
        items.reserveCapacity(limit)
        for row in rows {
            for chip in row.chips {
                guard items.count < limit else { return items }
                let translation = translates ? model.translation(for: chip) : nil
                items.append(WallTagItem(
                    chip: chip, namespace: row.tag.namespace,
                    text: chip.content.chipText(translation: translation, showsImages: showsImages),
                    imageURL: showsImages ? translation?.valueImageURL : nil
                ))
            }
        }
        return items
    }

    private var actions: WallTagActions {
        WallTagActions(
            search: { keyword in
                searchCount += 1
                stack?.push(.search(keyword: keyword))
            },
            vote: { chip, vote in model.voteTag(chip, vote: vote) },
            showDetail: { detail in model.showTagDetail(detail) },
            expand: { withAnimation(.snappy) { isExpanded = true } }
        )
    }
}

/// One chip's values.
nonisolated struct WallTagItem: Identifiable, Equatable, Sendable {
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

/// The chips, laid out once per change of their values: the page's other updates (reading
/// progress, a favourite) do not reach them.
private struct WallTagChips: View, Equatable {
    let items: [WallTagItem]
    /// How many tags "+47" stands for; none when all are shown.
    let hidden: Int
    let fill: Color
    let translates: Bool
    let isLoggedIn: Bool
    let actions: WallTagActions

    @Environment(\.look) private var look

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.items == rhs.items && lhs.hidden == rhs.hidden && lhs.fill == rhs.fill
            && lhs.translates == rhs.translates && lhs.isLoggedIn == rhs.isLoggedIn
    }

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(items) { item in
                Button {
                    actions.search(item.chip.searchKeyword)
                } label: {
                    WallTagChip(item: item, fill: fill)
                }
                .buttonStyle(.plain)
                .contextMenu { menu(for: item.chip) }
            }
            if hidden > 0 {
                Button(action: actions.expand) {
                    Text(verbatim: L10n.Localizable.Gallery.Tags.more(hidden))
                        .font(.footnote)
                        .monospacedDigit()
                        .foregroundStyle(look.secondaryLabel)
                        .padding(.horizontal, 11)
                        .frame(minHeight: WallTagChip.height)
                        .background(fill, in: .capsule)
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// "Detail" only while translating, for a tag whose translation has a description; votes
    /// only with an account: withdraw when voted, else up or down.
    @ViewBuilder
    private func menu(for chip: DetailTagChip) -> some View {
        if translates, let detail = chip.detail {
            Button(L10n.Localizable.DetailView.ContextMenu.Button.detail, systemImage: "doc.richtext") {
                actions.showDetail(detail)
            }
        }
        if isLoggedIn {
            if chip.hasVote {
                Button {
                    actions.vote(chip, chip.withdrawVote)
                } label: {
                    Label(
                        L10n.Localizable.DetailView.ContextMenu.Button.withdrawVote,
                        systemImage: chip.content.isVotedUp ? "hand.thumbsup.fill" : "hand.thumbsdown.fill"
                    )
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

/// A chip: 28 high, a 7 pt dot in the namespace's hue, the tag, and its image when tag
/// images are on. A tag the site marks as weak is set in the secondary colour.
private struct WallTagChip: View {
    let item: WallTagItem
    let fill: Color

    @Environment(\.look) private var look

    static let height: CGFloat = 28

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill((item.namespace ?? .other).markColor)
                .frame(width: 7, height: 7)
                .accessibilityHidden(true)
            Text(verbatim: item.text)
                .font(.footnote)
                .foregroundStyle(item.chip.content.isWeak ? look.secondaryLabel : look.label)
                .lineLimit(1)
            if let imageURL = item.imageURL {
                RemoteImage(url: imageURL, size: CGSize(width: 16, height: 16), cornerRadius: 3)
            }
        }
        .padding(.leading, 9)
        .padding(.trailing, 11)
        .frame(minHeight: Self.height)
        .background(fill, in: .capsule)
        .contentShape(.capsule)
    }
}
