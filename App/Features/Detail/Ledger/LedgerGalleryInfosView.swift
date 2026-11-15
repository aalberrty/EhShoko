import EhFeatures
import EhModels
import SwiftUI

/// Gallery infos (`ledger.md` section 4, child screens): the facts table continued, every
/// field v3 lists as a label over its value in two ruled columns (one at accessibility sizes).
/// A tap copies a value.
struct LedgerGalleryInfosView: View {
    @State private var model: GalleryInfosModel
    @State private var hud: HUDConfiguration?

    @Environment(\.look) private var look
    @Environment(\.dynamicTypeSize) private var typeSize

    init(gallery: Gallery, detail: GalleryDetail) {
        _model = State(initialValue: GalleryInfosModel(gallery: gallery, detail: detail))
    }

    var body: some View {
        ScrollView {
            LedgerRuledTable(items: rows, columns: typeSize.isAccessibilitySize ? 1 : 2) { row in
                Button {
                    if let value = row.value { model.copy(value) }
                } label: {
                    LedgerLabelledCell(label: row.title) {
                        Text(row.value ?? L10n.Localizable.GalleryInfosView.Value.none)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(row.value == nil ? look.tertiaryLabel : look.label)
                            .multilineTextAlignment(.leading)
                            .lineLimit(4)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .disabled(row.value == nil)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .background { look.background.ignoresSafeArea() }
        .navigationTitle(L10n.Localizable.GalleryInfosView.Title.galleryInfos)
        .navigationBarTitleDisplayMode(.inline)
        .hud($hud)
        .onChange(of: model.copyCount) { hud = .copiedToClipboard }
        .sensoryFeedback(.success, trigger: model.copyCount)
    }

    /// v3's fields, in v3's order.
    private var rows: [InfoRow] {
        typealias Title = L10n.Localizable.GalleryInfosView.Title
        let gallery = model.gallery
        let detail = model.detail
        let yes = L10n.Localizable.GalleryInfosView.Value.yes
        let no = L10n.Localizable.GalleryInfosView.Value.no
        return [
            InfoRow(Title.id, detail.gid),
            InfoRow(Title.token, gallery.token),
            InfoRow(Title.title, detail.title),
            InfoRow(Title.japaneseTitle, detail.jpnTitle),
            InfoRow(Title.galleryURL, gallery.galleryURL?.absoluteString),
            InfoRow(Title.coverURL, detail.coverURL?.absoluteString),
            InfoRow(Title.archiveURL, detail.archiveURL?.absoluteString),
            InfoRow(Title.torrentURL, model.torrentURL.absoluteString),
            InfoRow(Title.parentURL, detail.parentURL?.absoluteString),
            InfoRow(Title.category, detail.category.localizedName),
            InfoRow(Title.uploader, detail.uploader),
            InfoRow(Title.postedDate, detail.formattedDateString),
            InfoRow(Title.visibility, detail.visibility.localizedName),
            InfoRow(Title.language, detail.language.localizedName),
            InfoRow(Title.pageCount, String(detail.pageCount)),
            InfoRow(Title.fileSize, detail.sizeCount.formatted() + " " + detail.sizeType),
            InfoRow(Title.favoritedTimes, String(detail.favoritedCount)),
            InfoRow(Title.favorited, detail.isFavorited ? yes : no),
            InfoRow(Title.ratingCount, String(detail.ratingCount)),
            InfoRow(Title.averageRating, detail.rating.formatted(.number.precision(.fractionLength(2)))),
            InfoRow(Title.myRating, detail.userRating == 0 ? nil : detail.userRating.formatted()),
            InfoRow(Title.torrentCount, String(detail.torrentCount)),
        ]
    }
}

private struct InfoRow: Identifiable {
    let title: String
    let value: String?

    var id: String { title }

    init(_ title: String, _ value: String?) {
        self.title = title
        self.value = value
    }
}
