import EhCore
import EhFeatures
import EhModels
import SwiftUI

/// The panel of Wall's gallery page: everything but the cover, on the ground colour with a
/// rounded top, scrolling up over the cover and the backdrop.
///
/// It is content, so nothing on it is glass. The title, the credit and the line of facts
/// come from the list's data and are there in the first frame; the sections below them are
/// placeholders until the page arrives.
struct WallGalleryPanel: View {
    let model: GalleryDetailModel
    let metrics: WallGalleryMetrics
    let copy: (String) -> Void
    let signIn: () -> Void

    @Environment(SettingsStore.self) private var settings
    @Environment(\.look) private var look
    /// The parsed heading, the credit and the other title, once worked out.
    @State private var parsedTitles: WallGalleryTitles?

    /// A wide pushed page (an iPad below the pane's width) keeps its text in a column.
    private static let maxContentWidth: CGFloat = 640

    var body: some View {
        let input = titleInput
        let titles = parsedTitles ?? WallGalleryTitles(unparsed: input)
        VStack(alignment: .leading, spacing: 0) {
            if !metrics.isPane {
                grabber
            }
            WallGalleryHeading(model: model, titles: titles, metrics: metrics, copy: copy)
            WallGalleryActions(model: model, metrics: metrics, signIn: signIn)
                .padding(.top, 16)
            sections(titles: titles)
        }
        .padding(.horizontal, metrics.panelPadding)
        .padding(.top, metrics.isPane ? 16 : 0)
        .padding(.bottom, 28)
        .frame(maxWidth: Self.maxContentWidth)
        .frame(maxWidth: .infinity)
        .background(alignment: .top) {
            // Reaches far below the last section, so a short page and the bounce at its end
            // show the ground and not the backdrop.
            UnevenRoundedRectangle(
                topLeadingRadius: metrics.panelCornerRadius, topTrailingRadius: metrics.panelCornerRadius,
                style: .continuous
            )
            .fill(metrics.ground(in: look))
            .padding(.bottom, -1_200)
        }
        // Again when the page brings the Japanese title or the tags, which decide between a
        // tag search and a quoted name.
        .task(id: input) {
            let titles = await WallGalleryTitles.make(from: input)
            if !Task.isCancelled, titles != parsedTitles {
                parsedTitles = titles
            }
        }
    }

    private var titleInput: WallGalleryTitles.Input {
        let detail = model.detail
        return WallGalleryTitles.Input(
            shown: model.title(prefersJapanese: settings.displaysJapaneseTitle),
            title: detail?.title ?? model.gallery.title, japaneseTitle: detail?.jpnTitle,
            tags: model.tagRows.isEmpty ? model.gallery.tags : model.tagRows.map(\.tag),
            uploader: model.uploader
        )
    }

    private var grabber: some View {
        Capsule()
            .fill(look.tertiaryLabel)
            .frame(width: 36, height: 5)
            .frame(maxWidth: .infinity)
            .padding(.top, 7)
            .padding(.bottom, 12)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private func sections(titles: WallGalleryTitles) -> some View {
        if model.detail != nil {
            if let error = model.loadingState.failed {
                WallGalleryOfflineNote(isNetworkError: error.isNetworkError) { model.refetch() }
            }
            WallGalleryTags(model: model, metrics: metrics)
            WallGalleryPreviewStrip(model: model, metrics: metrics)
            if let other = titles.other {
                WallGalleryOtherTitle(text: other, copyable: titles.copyable, copy: copy)
            }
        } else if let error = model.loadingState.failed {
            ErrorStateView(error: error, retry: error.isRetryable ? { model.refetch() } : nil)
                .padding(.top, 24)
        } else {
            WallGalleryPlaceholders(metrics: metrics)
        }
    }
}

// MARK: Title, credit, facts

/// The title, who made it, and one line of facts.
private struct WallGalleryHeading: View {
    let model: GalleryDetailModel
    let titles: WallGalleryTitles
    let metrics: WallGalleryMetrics
    let copy: (String) -> Void

    @Environment(\.look) private var look
    @State private var showsFullTitle = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            title
            if let credit = titles.credit {
                WallGalleryCreditLine(credit: credit)
            }
            WallGalleryFacts(model: model)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Up to three lines; a tap shows all of it, a long press copies either full title.
    private var title: some View {
        Text(verbatim: titles.heading)
            .font(metrics.isPane ? .title3.bold() : .title2.bold())
            .lookTitleDesign()
            .foregroundStyle(look.label)
            .multilineTextAlignment(.leading)
            .lineLimit(showsFullTitle ? nil : 3)
            .fixedSize(horizontal: false, vertical: true)
            .contentShape(.rect)
            .onTapGesture {
                withAnimation(.snappy) { showsFullTitle.toggle() }
            }
            .contextMenu { WallGalleryCopyMenu(titles: titles.copyable, copy: copy) }
            .accessibilityAddTraits(.isHeader)
    }
}

/// "Copy", with each full title the gallery has as an entry.
private struct WallGalleryCopyMenu: View {
    let titles: [String]
    let copy: (String) -> Void

    var body: some View {
        Section(L10n.Localizable.ReadingView.ContextMenu.Button.copy) {
            ForEach(titles, id: \.self) { title in
                Button {
                    copy(title)
                } label: {
                    Label {
                        Text(verbatim: title)
                    } icon: {
                        Image(systemName: "doc.on.doc")
                    }
                }
            }
        }
    }
}

/// The category in its hue, the rating with its count, pages, language and size, wrapping.
private struct WallGalleryFacts: View {
    let model: GalleryDetailModel

    @Environment(\.look) private var look

    var body: some View {
        let detail = model.detail
        let facts = Self.facts(pageCount: model.pageCount, language: language, detail: detail)
        // Each fact carries the dot that follows it, so a wrapped line never starts with one.
        FlowLayout(spacing: 7, lineSpacing: 3) {
            HStack(spacing: 5) {
                CategoryMark(model.gallery.category, style: .dot)
                CategoryMark(model.gallery.category, style: .name)
                    .fontWeight(.semibold)
                separator
                    .padding(.leading, 2)
            }
            HStack(spacing: 4) {
                RatingFigure(rating: Double(detail?.rating ?? model.gallery.rating))
                    .fontWeight(.semibold)
                    .foregroundStyle(look.label)
                if let detail {
                    Text(verbatim: "(\(detail.ratingCount.formatted()))")
                        .monospacedDigit()
                }
                if !facts.isEmpty {
                    separator
                        .padding(.leading, 3)
                }
            }
            ForEach(Array(facts.enumerated()), id: \.offset) { index, fact in
                HStack(spacing: 7) {
                    Text(verbatim: fact)
                        .monospacedDigit()
                    if index < facts.count - 1 {
                        separator
                    }
                }
            }
        }
        .font(.footnote)
        .lineLimit(1)
        .foregroundStyle(look.secondaryLabel)
    }

    private var separator: some View {
        Text(verbatim: "·")
            .accessibilityHidden(true)
    }

    private var language: Language? {
        model.detail?.language ?? model.gallery.language
    }

    private static func facts(pageCount: Int, language: Language?, detail: GalleryDetail?) -> [String] {
        var facts: [String] = []
        if pageCount > 0 {
            facts.append(L10n.Localizable.Common.Value.pages(pageCount.formatted()))
        }
        if let language {
            facts.append(language.localizedName)
        }
        if let detail, detail.sizeCount > 0 {
            facts.append(detail.sizeCount.formatted() + " " + detail.sizeType)
        }
        return facts
    }
}

// MARK: Under the sections

/// The other title as the site has it, groups and all, which Wall's drawing leaves out:
/// here it closes the panel, and a long press copies either full title.
private struct WallGalleryOtherTitle: View {
    let text: String
    let copyable: [String]
    let copy: (String) -> Void

    @Environment(\.look) private var look

    var body: some View {
        Text(verbatim: text)
            .font(.caption)
            .foregroundStyle(look.secondaryLabel)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 20)
            .contentShape(.rect)
            .contextMenu { WallGalleryCopyMenu(titles: copyable, copy: copy) }
    }
}

/// A reload failed and the page shown is the stored one.
private struct WallGalleryOfflineNote: View {
    let isNetworkError: Bool
    let retry: () -> Void

    @Environment(\.look) private var look

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isNetworkError ? "wifi.slash" : "exclamationmark.triangle")
                .foregroundStyle(look.secondaryLabel)
            Text(L10n.Localizable.Gallery.offline)
                .foregroundStyle(look.label)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(L10n.Localizable.ErrorView.Button.retry, action: retry)
                .fontWeight(.semibold)
                .foregroundStyle(look.label)
        }
        .font(.footnote)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(look.fill3, in: .rect(cornerRadius: 14, style: .continuous))
        .padding(.top, 16)
    }
}

/// Stand-ins for the tags and the previews while the page loads, in the sections' places
/// and sizes, so nothing jumps when they arrive.
private struct WallGalleryPlaceholders: View {
    let metrics: WallGalleryMetrics

    @Environment(\.look) private var look

    private static let chipWidths: [CGFloat] = [96, 118, 72, 84, 104, 66, 90]

    var body: some View {
        let fill = metrics.fill(in: look)
        VStack(alignment: .leading, spacing: 9) {
            WallSectionHeader(title: L10n.Localizable.Gallery.tags)
            FlowLayout(spacing: 6) {
                ForEach(Self.chipWidths, id: \.self) { width in
                    Capsule()
                        .fill(fill)
                        .frame(width: width, height: 28)
                }
            }
            WallSectionHeader(title: L10n.Localizable.Gallery.previews)
            HStack(spacing: 8) {
                ForEach(0..<4, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: WallPreviewThumbnail.cornerRadius, style: .continuous)
                        .fill(fill)
                        .frame(width: WallPreviewThumbnail.stripWidth, height: WallPreviewThumbnail.stripHeight)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// A section's heading in the look's style ("TAGS" under Wall), with an optional link at its
/// trailing end ("All 58 ›").
struct WallSectionHeader: View {
    let title: String
    var link: String?
    var action: () -> Void = {}

    @Environment(\.look) private var look

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .lookSectionHeader()
            Spacer(minLength: 0)
            if let link {
                Button(action: action) {
                    HStack(spacing: 2) {
                        Text(verbatim: link)
                            .monospacedDigit()
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(look.tertiaryLabel)
                    }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(look.label)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
        .lineLimit(1)
        .padding(.top, 18)
    }
}
