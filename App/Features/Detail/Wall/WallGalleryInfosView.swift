import EhFeatures
import EhModels
import SwiftUI

/// Every field of the gallery as a grouped list (`wall.md` section 4): what names it, its
/// links, what it is, and its figures. A tap on a value copies it.
struct WallGalleryInfosView: View {
    @State private var model: GalleryInfosModel
    @State private var hud: HUDConfiguration?

    @Environment(\.look) private var look

    init(gallery: Gallery, detail: GalleryDetail) {
        _model = State(initialValue: GalleryInfosModel(gallery: gallery, detail: detail))
    }

    var body: some View {
        List {
            ForEach(Array(groups.enumerated()), id: \.offset) { _, rows in
                Section {
                    ForEach(rows) { row in
                        WallInfoRow(row: row) { model.copy($0) }
                    }
                }
                .listRowBackground(look.raised)
                .listRowSeparatorTint(look.separator)
            }
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

    private var groups: [[WallInfo]] {
        typealias Title = L10n.Localizable.GalleryInfosView.Title
        let gallery = model.gallery
        let detail = model.detail
        let yes = L10n.Localizable.GalleryInfosView.Value.yes
        let no = L10n.Localizable.GalleryInfosView.Value.no
        return [
            [
                WallInfo(Title.title, detail.title),
                WallInfo(Title.japaneseTitle, detail.jpnTitle),
                WallInfo(Title.id, detail.gid),
                WallInfo(Title.token, gallery.token),
            ],
            [
                WallInfo(Title.category, detail.category.localizedName),
                WallInfo(Title.uploader, detail.uploader),
                WallInfo(Title.postedDate, detail.formattedDateString),
                WallInfo(Title.visibility, detail.visibility.localizedName),
                WallInfo(Title.language, detail.language.localizedName),
                WallInfo(Title.pageCount, String(detail.pageCount)),
                WallInfo(Title.fileSize, detail.sizeCount.formatted(.number.precision(.fractionLength(0...2))) + " " + detail.sizeType),
            ],
            [
                WallInfo(Title.favoritedTimes, String(detail.favoritedCount)),
                WallInfo(Title.favorited, detail.isFavorited ? yes : no),
                WallInfo(Title.ratingCount, String(detail.ratingCount)),
                WallInfo(Title.averageRating, detail.rating.formatted(.number.precision(.fractionLength(2)))),
                WallInfo(Title.myRating, detail.userRating == 0 ? nil : detail.userRating.formatted()),
                WallInfo(Title.torrentCount, String(detail.torrentCount)),
            ],
            [
                WallInfo(Title.galleryURL, gallery.galleryURL?.absoluteString),
                WallInfo(Title.coverURL, detail.coverURL?.absoluteString),
                WallInfo(Title.archiveURL, detail.archiveURL?.absoluteString),
                WallInfo(Title.torrentURL, model.torrentURL.absoluteString),
                WallInfo(Title.parentURL, detail.parentURL?.absoluteString),
            ],
        ]
    }
}

nonisolated private struct WallInfo: Identifiable, Equatable, Sendable {
    let title: String
    let value: String?

    var id: String { title }

    init(_ title: String, _ value: String?) {
        self.title = title
        self.value = value
    }
}

private struct WallInfoRow: View {
    let row: WallInfo
    let copy: (String) -> Void

    @Environment(\.look) private var look

    var body: some View {
        Button {
            if let value = row.value { copy(value) }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(verbatim: row.title)
                    .font(.subheadline)
                    .foregroundStyle(look.secondaryLabel)
                Spacer(minLength: 0)
                Text(verbatim: row.value ?? L10n.Localizable.GalleryInfosView.Value.none)
                    .font(.subheadline)
                    .foregroundStyle(row.value == nil ? look.tertiaryLabel : look.label)
                    .lineLimit(3)
                    .multilineTextAlignment(.trailing)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(row.value == nil)
    }
}
