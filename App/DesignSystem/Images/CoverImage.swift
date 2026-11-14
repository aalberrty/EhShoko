import Kingfisher
import SwiftUI

/// A gallery cover, decoded once at the site's size and drawn at whatever size a part shows it
/// (`Design/designs/README.md` section 9.3).
///
/// The part states the box it displays; the bitmap in the cache is the same for every box
/// (`CoverProcessor`), so opening a gallery from any list finds its cover decoded, which the
/// zoom transition needs. Originals go to the disk cache and the decoded bitmap to the memory
/// cache. Loads are cancelled when the view disappears. The placeholder is a flat fill from the
/// look, with no spinner, so a fast scroll draws nothing that animates; a failed load shows a
/// photo symbol on the look's surface. Decorative to VoiceOver: label the containing cell.
struct CoverImage: View {
    private enum Sizing {
        case fixed(CGSize)
        case aspect(CGFloat)
    }

    private let url: URL?
    private let sizing: Sizing
    private let contentMode: SwiftUI.ContentMode
    private let cornerRadius: CGFloat
    @Environment(\.look) private var look

    /// A fixed box, such as a row's cover. `.fill` covers and clips it; `.fit` letterboxes
    /// inside it with the corners on the image (v3's row cover).
    init(
        url: URL?, size: CGSize, contentMode: SwiftUI.ContentMode = .fill,
        cornerRadius: CGFloat = Tokens.Radius.image
    ) {
        self.url = url
        sizing = .fixed(size)
        self.contentMode = contentMode
        self.cornerRadius = cornerRadius
    }

    /// Fills the proposed width at `aspectRatio` (width / height), such as a grid cell, and
    /// covers that box.
    init(url: URL?, aspectRatio: CGFloat = Tokens.Aspect.cover, cornerRadius: CGFloat = Tokens.Radius.image) {
        self.url = url
        sizing = .aspect(aspectRatio)
        contentMode = .fill
        self.cornerRadius = cornerRadius
    }

    /// The options a list's prefetcher uses, so a prefetched cover is the entry `CoverImage`
    /// finds (`ImagePrefetcher(urls:options:)`).
    static let prefetchOptions: KingfisherOptionsInfo = [
        .processor(CoverProcessor.shared), .cacheOriginalImage, .cacheMemoryOnly,
    ]

    var body: some View {
        content
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var content: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        switch sizing {
        case .fixed(let size) where contentMode == .fit:
            image
                .aspectRatio(contentMode: .fit)
                .clipShape(shape)
                .frame(width: size.width, height: size.height)
        case .fixed(let size):
            Color.clear
                .frame(width: size.width, height: size.height)
                .overlay { image.aspectRatio(contentMode: .fill) }
                .clipShape(shape)
                .contentShape(shape)
        case .aspect(let ratio):
            Color.clear
                .aspectRatio(ratio, contentMode: .fit)
                .overlay { image.aspectRatio(contentMode: .fill) }
                .clipShape(shape)
                .contentShape(shape)
        }
    }

    private var image: KFImage {
        KFImage(url)
            .setProcessor(CoverProcessor.shared)
            .cacheOriginalImage()
            .cacheMemoryOnly()
            .cancelOnDisappear(true)
            .fade(duration: Tokens.Duration.imageFade)
            .placeholder { [look] in
                Rectangle().fill(look.fill2)
            }
            .onFailureView { [look] in
                Rectangle()
                    .fill(look.surface)
                    .overlay {
                        Image(systemName: "photo")
                            .font(.title3)
                            .foregroundStyle(look.tertiaryLabel)
                    }
            }
            .resizable()
    }
}
