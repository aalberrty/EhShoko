#if DEBUG || HARNESS
import EhCore
import EhFeatures
import EhModels
import SwiftUI

/// v3's list (`GalleryCollection` in the detail mode) with one change: the row's cover is a
/// `CoverImage`, decoded once at the site's size, instead of a `RemoteImage` decoded at the
/// row's display size. Everything else is `GalleryDetailRow` as it is, so a run against
/// `v3-rows` measures the cover pipeline alone.
struct ListHarnessCoverRows: View {
    let galleries: [Gallery]
    @Environment(StackRouter.self) private var stack

    var body: some View {
        List {
            ForEach(galleries) { gallery in
                Button {
                    stack.push(.detail(gallery))
                } label: {
                    ListHarnessCoverRow(gallery: gallery)
                }
                .foregroundStyle(.primary)
            }
        }
        .listStyle(.plain)
    }
}

private struct ListHarnessCoverRow: View {
    let gallery: Gallery
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        HStack(alignment: .top, spacing: Tokens.Spacing.medium) {
            CoverImage(url: gallery.coverURL, size: Tokens.ImageSize.row, contentMode: .fit)
            VStack(alignment: .leading, spacing: 5) {
                Text(gallery.title)
                    .font(.headline)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                if let uploader = gallery.uploader, !uploader.isEmpty {
                    Text(uploader)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if settings.showsTagsInList {
                    let tags = gallery.tagContents(maximum: settings.listTagsNumberMaximum)
                    if !tags.isEmpty {
                        ListTagCloud(tags: tags)
                    }
                }
                Spacer(minLength: 0)
                HStack {
                    RatingStars(rating: Double(gallery.rating))
                        .font(.caption)
                        .foregroundStyle(.yellow)
                    Spacer()
                    GalleryLanguageAndPages(gallery: gallery)
                        .minimumScaleFactor(0.75)
                }
                HStack(alignment: .bottom) {
                    CategoryLabel(gallery.category.localizedName, color: gallery.color(for: settings.galleryHost))
                    Spacer()
                    Text(gallery.formattedDateString)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }
            .frame(minHeight: Tokens.ImageSize.row.height)
        }
        .padding(.vertical, Tokens.Spacing.xSmall)
        .accessibilityElement(children: .combine)
    }
}
#endif
