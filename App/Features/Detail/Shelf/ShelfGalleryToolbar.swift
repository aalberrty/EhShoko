import EhFeatures
import EhModels
import SwiftUI

/// The page's top bar (`shelf.md` section 4, item 1): the system's Back, then Share and More,
/// which the system draws as one glass group. More holds Gallery infos, Similar galleries,
/// Archive and Torrents; it opens once the page has loaded.
///
/// v3 has no tag-voting screen to list here: tags are voted on from each tag's long-press
/// menu, as in v3.
struct ShelfGalleryToolbar: ToolbarContent {
    let model: GalleryDetailModel
    let similar: (String) -> Void

    var body: some ToolbarContent {
        if let url = model.gallery.galleryURL {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: url) {
                    Label(L10n.Localizable.DetailView.ToolbarItem.Button.share, systemImage: "square.and.arrow.up")
                }
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            ToolbarFeaturesMenu {
                Button(L10n.Localizable.GalleryInfosView.Title.galleryInfos, systemImage: "info.circle") {
                    model.destination = .galleryInfos
                }
                Button(L10n.Localizable.Gallery.Action.similar, systemImage: "photo.on.rectangle.angled") {
                    if let keyword = model.similarGalleryKeyword { similar(keyword) }
                }
                Section {
                    Button(L10n.Localizable.Gallery.Action.archive, systemImage: "arrow.down.circle") {
                        model.showArchives()
                    }
                    .disabled(!model.canOpenArchives)
                    Button(torrentsTitle, systemImage: "square.and.arrow.down") {
                        model.showTorrents()
                    }
                    .disabled(model.torrentCount == 0)
                }
            }
            .disabled(!model.isMenuEnabled)
        }
    }

    private var torrentsTitle: String {
        let count = model.torrentCount
        return count > 0 ? L10n.Localizable.Gallery.Action.Torrents.count(count) : L10n.Localizable.Gallery.Action.torrents
    }
}
