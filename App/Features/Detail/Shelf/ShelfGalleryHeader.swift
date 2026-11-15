import EhCore
import EhFeatures
import EhModels
import SwiftUI
import UIKit

/// The top of Shelf's gallery page (`shelf.md` section 4, items 2 and 3): the cover beside the
/// category and event, the title, the credit and who uploaded it when; beneath, the other title
/// in full. Everything here can be drawn from the list's data, so it is in the page's first
/// frame and stays when the page fails to load.
struct ShelfGalleryHeader: View {
    let model: GalleryDetailModel
    /// After the other title was copied, for the page's HUD (a HUD inside the scrolling page
    /// would scroll with it).
    let copied: () -> Void

    @Environment(SettingsStore.self) private var settings
    @State private var titles: ShelfGalleryTitles?

    static let coverSize = CGSize(width: 132, height: 189)

    var body: some View {
        let source = ShelfGalleryTitles.Source(
            title: model.detail?.title ?? model.gallery.title, japaneseTitle: model.detail?.jpnTitle,
            prefersJapanese: settings.displaysJapaneseTitle
        )
        // Made in the first frame, before it is drawn, and again only when a title changes.
        let shown = titles ?? ShelfGalleryTitles(source)
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                ShelfGalleryCover(url: model.gallery.coverURL ?? model.detail?.coverURL)
                ShelfGalleryHeading(model: model, titles: shown)
            }
            .padding(.leading, 20)
            .padding(.trailing, 16)
            if let other = shown.other {
                ShelfGalleryOtherTitle(text: other, copied: copied)
                    .padding(.top, 12)
            }
        }
        .onChange(of: source, initial: true) { _, source in
            titles = ShelfGalleryTitles(source)
        }
    }
}

/// The cover, with a soft shadow under it. The bitmap is the one the list decoded, so the zoom
/// from the list's cover finds it.
private struct ShelfGalleryCover: View {
    let url: URL?

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        CoverImage(url: url, size: ShelfGalleryHeader.coverSize, cornerRadius: 12)
            // The shadow is cast by a plain shape behind the image, which Core Animation draws
            // from its path, not from the image's pixels.
            .background {
                shape
                    .fill(.black)
                    .shadow(color: .black.opacity(0.28), radius: 15, y: 10)
            }
            .overlay { shape.strokeBorder(.gray.opacity(0.35), lineWidth: 0.5) }
    }
}

/// The category and event capsules, the title, the credit and "Uploaded by … · 2 h ago".
private struct ShelfGalleryHeading: View {
    let model: GalleryDetailModel
    let titles: ShelfGalleryTitles

    @Environment(\.look) private var look

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                CategoryMark(model.gallery.category, style: .capsule)
                if let event = titles.parsed.event {
                    Text(event)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(look.secondaryLabel)
                        .lineLimit(1)
                        .padding(.horizontal, 7)
                        .frame(minHeight: 20)
                        .background(look.fill3, in: .capsule)
                }
            }
            Text(titles.heading)
                .font(.title3.bold())
                .lookTitleDesign()
                .foregroundStyle(look.label)
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
                .accessibilityAddTraits(.isHeader)
            if let credit = titles.credit {
                ShelfGalleryCredit(model: model, titles: titles, credit: credit)
                    .padding(.top, 6)
            }
            Spacer(minLength: Tokens.Spacing.small)
            ShelfGalleryUploader(model: model)
        }
        .frame(maxWidth: .infinity, minHeight: ShelfGalleryHeader.coverSize.height, alignment: .topLeading)
    }
}

/// The credit in the tint. A tap searches the one name it holds; with several, it offers each.
private struct ShelfGalleryCredit: View {
    let model: GalleryDetailModel
    let titles: ShelfGalleryTitles
    let credit: String

    @Environment(StackRouter.self) private var stack: StackRouter?

    var body: some View {
        Group {
            if titles.creditHasSeveralNames {
                Menu {
                    // Built when the menu opens.
                    ForEach(searches) { target in
                        Button(L10n.Localizable.List.Action.searchArtist(target.name), systemImage: target.systemImage) {
                            stack?.push(.search(keyword: target.keyword))
                        }
                    }
                } label: {
                    label
                }
            } else {
                Button {
                    if let target = searches.first {
                        stack?.push(.search(keyword: target.keyword))
                    }
                } label: {
                    label
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var label: some View {
        Text(credit)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.tint)
            .lineLimit(2)
            .multilineTextAlignment(.leading)
    }

    private var searches: [GalleryCreditSearch] {
        titles.creditSearches(in: model.gallery, tags: model.tagRows.map(\.tag))
    }
}

/// "Uploaded by lantern_scans · 2 h ago". The name is a link that searches the uploader.
private struct ShelfGalleryUploader: View {
    let model: GalleryDetailModel

    @Environment(StackRouter.self) private var stack: StackRouter?
    @Environment(\.look) private var look

    /// Stands for the uploader's search inside the line; never leaves the view.
    private static let uploaderLink = URL(string: "ehshoko-gallery:uploader")

    var body: some View {
        if let uploader = model.uploader, !uploader.isEmpty {
            Text(line(uploader: uploader))
                .font(.footnote)
                .foregroundStyle(look.secondaryLabel)
                .tint(look.secondaryLabel)
                .lineLimit(2)
                .environment(\.openURL, OpenURLAction { _ in
                    stack?.push(.search(keyword: DetailSearchKeyword.uploader(uploader)))
                    return .handled
                })
        }
    }

    private func line(uploader: String) -> AttributedString {
        let posted = (model.detail?.postedDate ?? model.gallery.postedDate)
            .formatted(.relative(presentation: .numeric, unitsStyle: .abbreviated))
        var line = AttributedString(L10n.Localizable.Gallery.uploadedBy(uploader, posted))
        if let range = line.range(of: uploader) {
            line[range].link = Self.uploaderLink
            line[range].font = .footnote.weight(.medium)
        }
        return line
    }
}

/// The other title in full, two lines with a chevron that expands it. A long press copies it.
private struct ShelfGalleryOtherTitle: View {
    let text: String
    let copied: () -> Void

    @Environment(\.look) private var look
    @State private var isExpanded = false

    var body: some View {
        HStack(spacing: 10) {
            Text(text)
                .font(.caption)
                .foregroundStyle(look.secondaryLabel)
                .lineLimit(isExpanded ? nil : 2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.disabled)
            Image(systemName: "chevron.down")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(look.secondaryLabel)
                .rotationEffect(.degrees(isExpanded ? 180 : 0))
                .accessibilityHidden(true)
        }
        .padding(.leading, 20)
        .padding(.trailing, 16)
        .contentShape(.rect)
        .onTapGesture {
            withAnimation(.snappy) { isExpanded.toggle() }
        }
        .onLongPressGesture(perform: copy)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: L10n.Localizable.ReadingView.ContextMenu.Button.copy, copy)
    }

    private func copy() {
        UIPasteboard.general.string = text
        copied()
    }
}
