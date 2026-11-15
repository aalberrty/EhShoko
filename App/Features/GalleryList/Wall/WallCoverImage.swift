import Kingfisher
import SwiftUI

/// A cover on Wall's wall: the bitmap every part shares, over the cell's own tile.
///
/// It asks for the cover exactly as `CoverImage` does, with `CoverProcessor` and the same
/// caching, so it is the same cache entry, decoded once at the site's size whatever a cell's
/// width is (`Design/designs/README.md` section 9.3). It differs in what shows without the
/// image, which `CoverImage` fixes: nothing while it loads, so the cell's tile in the
/// category's tint shows through, and "Cover not saved" on the look's surface when it could
/// not be loaded (`wall.md` section 3, "States").
struct WallCoverImage: View {
    let url: URL?
    let look: Look

    var body: some View {
        KFImage(url)
            .setProcessor(CoverProcessor.shared)
            .cacheOriginalImage()
            .cacheMemoryOnly()
            .cancelOnDisappear(true)
            .fade(duration: Tokens.Duration.imageFade)
            .onFailureView { [look] in
                WallCoverMissing(look: look)
            }
            .resizable()
            .aspectRatio(contentMode: .fill)
    }
}

/// A cover that failed, or is not saved while offline: a photo symbol and "Cover not saved".
private struct WallCoverMissing: View {
    let look: Look

    var body: some View {
        look.surface
            .overlay {
                VStack(spacing: 4) {
                    Image(systemName: "photo")
                        .font(.body)
                    Text(L10n.Localizable.List.Cover.missing)
                        .font(WallCellFonts.missing)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                }
                .foregroundStyle(look.tertiaryLabel)
                .padding(4)
            }
    }
}
