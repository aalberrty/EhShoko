import EhFeatures
import EhModels
import SwiftUI

/// Every field of the gallery as a grouped list (`shelf.md` section 4, "Gallery infos"); a tap
/// on a value copies it.
struct ShelfGalleryInfosScreen: View {
    @State private var model: GalleryInfosModel
    @State private var hud: HUDConfiguration?

    @Environment(\.look) private var look

    init(gallery: Gallery, detail: GalleryDetail) {
        _model = State(initialValue: GalleryInfosModel(gallery: gallery, detail: detail))
    }

    var body: some View {
        List(rows) { row in
            Button {
                if let value = row.value { model.copy(value) }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: Tokens.Spacing.medium) {
                    Text(row.title)
                        .foregroundStyle(look.label)
                    Spacer(minLength: Tokens.Spacing.small)
                    Text(row.value ?? L10n.Localizable.GalleryInfosView.Value.none)
                        .font(.subheadline)
                        .foregroundStyle(row.value == nil ? AnyShapeStyle(look.tertiaryLabel) : AnyShapeStyle(look.secondaryLabel))
                        .lineLimit(3)
                        .multilineTextAlignment(.trailing)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(row.value == nil)
            .listRowBackground(look.raised)
            .listRowSeparatorTint(look.separator)
            .accessibilityHint(row.value == nil ? "" : L10n.Localizable.ReadingView.ContextMenu.Button.copy)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(look.surface)
        .navigationTitle(L10n.Localizable.GalleryInfosView.Title.galleryInfos)
        .navigationBarTitleDisplayMode(.inline)
        .hud($hud)
        .onChange(of: model.copyCount) { hud = .copiedToClipboard }
        .sensoryFeedback(.success, trigger: model.copyCount)
    }

    private var rows: [ShelfInfoRow] {
        typealias Title = L10n.Localizable.GalleryInfosView.Title
        let gallery = model.gallery
        let detail = model.detail
        let yes = L10n.Localizable.GalleryInfosView.Value.yes
        let no = L10n.Localizable.GalleryInfosView.Value.no
        return [
            ShelfInfoRow(Title.id, detail.gid),
            ShelfInfoRow(Title.token, gallery.token),
            ShelfInfoRow(Title.title, detail.title),
            ShelfInfoRow(Title.japaneseTitle, detail.jpnTitle),
            ShelfInfoRow(Title.galleryURL, gallery.galleryURL?.absoluteString),
            ShelfInfoRow(Title.coverURL, detail.coverURL?.absoluteString),
            ShelfInfoRow(Title.archiveURL, detail.archiveURL?.absoluteString),
            ShelfInfoRow(Title.torrentURL, model.torrentURL.absoluteString),
            ShelfInfoRow(Title.parentURL, detail.parentURL?.absoluteString),
            ShelfInfoRow(Title.category, detail.category.localizedName),
            ShelfInfoRow(Title.uploader, detail.uploader),
            ShelfInfoRow(Title.postedDate, detail.formattedDateString),
            ShelfInfoRow(Title.visibility, detail.visibility.localizedName),
            ShelfInfoRow(Title.language, detail.language.localizedName),
            ShelfInfoRow(Title.pageCount, String(detail.pageCount)),
            ShelfInfoRow(Title.fileSize, detail.sizeCount.formatted() + " " + detail.sizeType),
            ShelfInfoRow(Title.favoritedTimes, String(detail.favoritedCount)),
            ShelfInfoRow(Title.favorited, detail.isFavorited ? yes : no),
            ShelfInfoRow(Title.ratingCount, String(detail.ratingCount)),
            ShelfInfoRow(Title.averageRating, detail.rating.formatted(.number.precision(.fractionLength(2)))),
            ShelfInfoRow(Title.myRating, detail.userRating == 0 ? nil : detail.userRating.formatted()),
            ShelfInfoRow(Title.torrentCount, String(detail.torrentCount)),
        ]
    }
}

private struct ShelfInfoRow: Identifiable {
    let title: String
    let value: String?

    var id: String { title }

    init(_ title: String, _ value: String?) {
        self.title = title
        self.value = value
    }
}
