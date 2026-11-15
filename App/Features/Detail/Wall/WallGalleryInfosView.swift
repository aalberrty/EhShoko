import EhFeatures
import EhModels
import SwiftUI

/// Gallery infos (`wall.md` section 4, "Child screens"): every field of the gallery as a
/// grouped list. A tap on a value copies it.
struct WallGalleryInfosView: View {
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
                        .foregroundStyle(row.value == nil ? look.tertiaryLabel : look.secondaryLabel)
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
        .background { look.surface.ignoresSafeArea() }
        .navigationTitle(L10n.Localizable.GalleryInfosView.Title.galleryInfos)
        .navigationBarTitleDisplayMode(.inline)
        .hud($hud)
        .onChange(of: model.copyCount) { hud = .copiedToClipboard }
        .sensoryFeedback(.success, trigger: model.copyCount)
    }

    private var rows: [WallInfoRow] {
        typealias Title = L10n.Localizable.GalleryInfosView.Title
        let gallery = model.gallery
        let detail = model.detail
        let yes = L10n.Localizable.GalleryInfosView.Value.yes
        let no = L10n.Localizable.GalleryInfosView.Value.no
        return [
            WallInfoRow(Title.id, detail.gid),
            WallInfoRow(Title.token, gallery.token),
            WallInfoRow(Title.title, detail.title),
            WallInfoRow(Title.japaneseTitle, detail.jpnTitle),
            WallInfoRow(Title.galleryURL, gallery.galleryURL?.absoluteString),
            WallInfoRow(Title.coverURL, detail.coverURL?.absoluteString),
            WallInfoRow(Title.archiveURL, detail.archiveURL?.absoluteString),
            WallInfoRow(Title.torrentURL, model.torrentURL.absoluteString),
            WallInfoRow(Title.parentURL, detail.parentURL?.absoluteString),
            WallInfoRow(Title.category, detail.category.localizedName),
            WallInfoRow(Title.uploader, detail.uploader),
            WallInfoRow(Title.postedDate, detail.formattedDateString),
            WallInfoRow(Title.visibility, detail.visibility.localizedName),
            WallInfoRow(Title.language, detail.language.localizedName),
            WallInfoRow(Title.pageCount, String(detail.pageCount)),
            WallInfoRow(Title.fileSize, detail.sizeCount.formatted() + " " + detail.sizeType),
            WallInfoRow(Title.favoritedTimes, String(detail.favoritedCount)),
            WallInfoRow(Title.favorited, detail.isFavorited ? yes : no),
            WallInfoRow(Title.ratingCount, String(detail.ratingCount)),
            WallInfoRow(Title.averageRating, detail.rating.formatted(.number.precision(.fractionLength(2)))),
            WallInfoRow(Title.myRating, detail.userRating == 0 ? nil : detail.userRating.formatted()),
            WallInfoRow(Title.torrentCount, String(detail.torrentCount)),
        ]
    }
}

private struct WallInfoRow: Identifiable {
    let title: String
    let value: String?

    var id: String { title }

    init(_ title: String, _ value: String?) {
        self.title = title
        self.value = value
    }
}
