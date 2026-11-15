import EhCore
import EhFeatures
import EhModels
import SwiftUI

/// The card's panel (`wall.md` section 4): rounded at its top, on the ground, scrolling up
/// over the cover. A grabber, the title, the credit, a line of facts, then the page: five
/// round actions, the tags, the previews and the other title.
///
/// The top three are drawn from the list's data, so they are in the card's first frame and
/// stay when the page fails to load; below them are placeholders until the page arrives.
struct WallGalleryPanel: View {
    let model: GalleryDetailModel
    let metrics: WallGalleryMetrics
    let actions: WallGalleryPanelActions

    @Environment(SettingsStore.self) private var settings
    @Environment(\.look) private var look
    @State private var titles: WallGalleryTitles?

    var body: some View {
        let source = WallGalleryTitles.Source(
            title: model.detail?.title ?? model.gallery.title, japaneseTitle: model.detail?.jpnTitle,
            prefersJapanese: settings.displaysJapaneseTitle
        )
        // Made in the first frame, before it is drawn, and again only when a title changes.
        let titles = titles.flatMap { $0.source == source ? $0 : nil } ?? WallGalleryTitles(source)
        VStack(alignment: .leading, spacing: 0) {
            if metrics.showsGrabber {
                Capsule()
                    .fill(look.tertiaryLabel)
                    .frame(width: 36, height: 5)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 7)
                    .padding(.bottom, 12)
                    .accessibilityHidden(true)
            }
            WallGalleryHeading(model: model, metrics: metrics, titles: titles, actions: actions)
            WallGallerySections(model: model, metrics: metrics, otherTitle: titles.other, actions: actions)
        }
        .padding(.horizontal, metrics.margin)
        .padding(.top, metrics.showsGrabber ? 0 : 16)
        .padding(.bottom, 28)
        // On a wide screen (a phone on its side, a card pushed on an iPad) the text keeps a
        // readable measure in the middle of the panel.
        .frame(maxWidth: WallGalleryMetrics.readableWidth, alignment: .leading)
        .frame(maxWidth: .infinity)
        .background(
            metrics.ground(look),
            in: UnevenRoundedRectangle(
                topLeadingRadius: metrics.panelCorner, topTrailingRadius: metrics.panelCorner, style: .continuous
            )
        )
        .onChange(of: source, initial: true) { _, source in
            self.titles = WallGalleryTitles(source)
        }
    }
}

/// The title, the credit and the line of facts.
private struct WallGalleryHeading: View {
    let model: GalleryDetailModel
    let metrics: WallGalleryMetrics
    let titles: WallGalleryTitles
    let actions: WallGalleryPanelActions

    @Environment(\.look) private var look
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(titles.heading)
                .font(metrics.titleFont)
                .lookTitleDesign()
                .foregroundStyle(look.label)
                .lineLimit(typeSize.isAccessibilitySize ? nil : 3)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                // A long press copies either title: the other one is at the panel's foot.
                .contextMenu {
                    Button(titles.shown, systemImage: "doc.on.doc") { actions.copy(titles.shown) }
                    if let other = titles.other {
                        Button(other, systemImage: "doc.on.doc") { actions.copy(other) }
                    }
                }
            if let credit = titles.credit {
                WallGalleryCredit(model: model, titles: titles, credit: credit, search: actions.search)
            }
            WallGalleryFacts(
                facts: WallGalleryFacts.Values(
                    category: model.detail?.category ?? model.gallery.category,
                    rating: Double(model.detail?.rating ?? model.gallery.rating),
                    ratingCount: model.detail?.ratingCount,
                    pageCount: model.pageCount,
                    language: (model.detail?.language ?? model.gallery.language).flatMap { language in
                        language == .invalid || language == .other ? nil : language.localizedName
                    },
                    size: model.detail.map { detail in
                        detail.sizeCount.formatted(.number.precision(.fractionLength(0...1))) + "\u{a0}" + detail.sizeType
                    }
                )
            )
            .equatable()
        }
    }
}

/// The credit with a small chevron. A tap searches the one name it holds; with several, it
/// offers each.
private struct WallGalleryCredit: View {
    let model: GalleryDetailModel
    let titles: WallGalleryTitles
    let credit: String
    let search: (String) -> Void

    @Environment(\.look) private var look

    var body: some View {
        Group {
            if titles.creditHasSeveralNames {
                Menu {
                    // Built when the menu opens.
                    ForEach(searches) { target in
                        Button(L10n.Localizable.List.Action.searchArtist(target.name), systemImage: target.systemImage) {
                            search(target.keyword)
                        }
                    }
                } label: {
                    label
                }
                .menuStyle(.button)
                .menuOrder(.fixed)
            } else {
                Button {
                    if let target = searches.first { search(target.keyword) }
                } label: {
                    label
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var label: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(credit)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(look.label)
                .multilineTextAlignment(.leading)
                .lineLimit(2)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(look.tertiaryLabel)
                .accessibilityHidden(true)
        }
        .contentShape(.rect)
    }

    private var searches: [GalleryCreditSearch] {
        titles.creditSearches(in: model.gallery, tags: model.tagRows.map(\.tag))
    }
}

/// One wrapping line: the category's dot and name in its hue, "★ 4.72 (318)", "48 pages", the
/// language, the size. The count of ratings and the size come with the page; the rest is the
/// list's.
private struct WallGalleryFacts: View, Equatable {
    nonisolated struct Values: Equatable {
        let category: EhModels.Category
        let rating: Double
        let ratingCount: Int?
        let pageCount: Int
        let language: String?
        let size: String?
    }

    let facts: Values

    @Environment(\.look) private var look

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.facts == rhs.facts
    }

    var body: some View {
        FlowLayout(spacing: 7, lineSpacing: 3) {
            HStack(spacing: 5) {
                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .fill(facts.category.markColor)
                    .frame(width: 7, height: 7)
                Text(facts.category.localizedName)
                    .fontWeight(.semibold)
                    .foregroundStyle(facts.category.markColor)
            }
            if facts.rating > 0 {
                separator
                rating
            }
            if facts.pageCount > 0 {
                separator
                Text(L10n.Localizable.List.pages(facts.pageCount))
                    .monospacedDigit()
            }
            if let language = facts.language {
                separator
                Text(language)
            }
            if let size = facts.size {
                separator
                Text(size)
                    .monospacedDigit()
            }
        }
        .font(.footnote)
        .foregroundStyle(look.secondaryLabel)
        .lineLimit(1)
        .accessibilityElement(children: .combine)
    }

    private var separator: some View {
        Text(verbatim: "·")
            .accessibilityHidden(true)
    }

    private var rating: some View {
        HStack(spacing: 3) {
            Image(systemName: "star.fill")
                .imageScale(.small)
                .foregroundStyle(look.label)
                .accessibilityHidden(true)
            Text(facts.rating, format: .number.precision(.fractionLength(2)))
                .fontWeight(.semibold)
                .monospacedDigit()
                .foregroundStyle(look.label)
            if let count = facts.ratingCount {
                Text(verbatim: "(\(count.formatted()))")
                    .monospacedDigit()
                    .accessibilityLabel(L10n.Localizable.Gallery.Figure.votes(count))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L10n.Localizable.Gallery.Figure.rating)
        .accessibilityValue(ratingValue)
    }

    private var ratingValue: String {
        let value = facts.rating.formatted(.number.precision(.fractionLength(2)))
        guard let count = facts.ratingCount else { return value }
        return value + ", " + L10n.Localizable.Gallery.Figure.votes(count)
    }
}

/// What follows the heading: the page once it is there; until then placeholders; what went
/// wrong when it failed. A saved page shown because the fetch failed has a line saying so.
private struct WallGallerySections: View {
    let model: GalleryDetailModel
    let metrics: WallGalleryMetrics
    let otherTitle: String?
    let actions: WallGalleryPanelActions

    var body: some View {
        if let failure = model.loadingState.failed, model.detail == nil || !failure.isRetryable {
            WallGalleryFailure(error: failure, retry: failure.isRetryable ? { model.refetch() } : nil)
                .padding(.top, Tokens.Spacing.xxLarge)
        } else if model.detail != nil {
            if let failure = model.loadingState.failed {
                ListOfflineBanner(form: .line(banner(for: failure)), retry: model.refetch)
                    .padding(.top, 14)
            }
            WallGalleryActions(model: model, metrics: metrics, signIn: actions.signIn)
                .padding(.top, 16)
            WallGalleryTags(model: model, metrics: metrics, search: actions.search)
            WallGalleryPreviews(model: model, metrics: metrics)
            if let otherTitle {
                WallGalleryOtherTitle(text: otherTitle, copy: actions.copy)
            }
        } else {
            WallGalleryPlaceholder(metrics: metrics)
                .padding(.top, 16)
        }
    }

    private func banner(for failure: AppError) -> String {
        failure == .networkingFailed ? L10n.Localizable.Gallery.offline : failure.headline ?? L10n.Localizable.Gallery.offline
    }
}

/// A section's heading on the panel: the look's section title ("TAGS" under Wall) with a link
/// at the trailing edge ("All 58 ›"), which is absent when there is nothing more to show.
struct WallGallerySectionHeading: View {
    let title: String
    var link: String?
    var action: () -> Void = {}

    @Environment(\.look) private var look

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .lookSectionHeader()
            Spacer(minLength: Tokens.Spacing.small)
            if let link {
                Button(action: action) {
                    HStack(spacing: 2) {
                        Text(link)
                            .monospacedDigit()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .accessibilityHidden(true)
                    }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(look.label)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 18)
    }
}

/// The other title in full at the foot of the panel, which Wall's drawing leaves out and the
/// app keeps. A long press copies it.
private struct WallGalleryOtherTitle: View {
    let text: String
    let copy: (String) -> Void

    @Environment(\.look) private var look

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(look.secondaryLabel)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 22)
            .contentShape(.rect)
            .onLongPressGesture { copy(text) }
            .accessibilityAction(named: L10n.Localizable.ReadingView.ContextMenu.Button.copy) { copy(text) }
    }
}

/// The page could not be loaded and nothing is stored: what went wrong, under the heading,
/// with Retry where trying again can help. It scrolls with the panel, so its button is a
/// fill, not glass.
private struct WallGalleryFailure: View {
    let error: AppError
    let retry: (() -> Void)?

    @Environment(\.look) private var look
    @Environment(\.onTint) private var onTint

    var body: some View {
        VStack(spacing: Tokens.Spacing.medium) {
            Image(systemName: error.symbol.rawValue)
                .font(.largeTitle)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(look.tertiaryLabel)
                .accessibilityHidden(true)
            VStack(spacing: Tokens.Spacing.xSmall) {
                if let headline = error.headline {
                    Text(headline)
                        .font(.headline)
                        .lookTitleDesign()
                        .foregroundStyle(look.label)
                }
                Text(error.alertText)
                    .font(.subheadline)
                    .foregroundStyle(look.secondaryLabel)
            }
            .multilineTextAlignment(.center)
            if let retry {
                Button(action: retry) {
                    Text(L10n.Localizable.ErrorView.Button.retry)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(onTint)
                        .padding(.horizontal, Tokens.Spacing.xLarge)
                        .frame(minHeight: 36)
                        .background(.tint, in: .capsule)
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .padding(.top, Tokens.Spacing.xSmall)
            }
        }
        .frame(maxWidth: .infinity)
    }
}
