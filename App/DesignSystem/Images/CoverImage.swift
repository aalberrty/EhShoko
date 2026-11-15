import Kingfisher
import SwiftUI

/// A gallery cover, decoded once at the site's size and drawn at whatever size a part shows it
/// (`Design/designs/README.md` section 9.3).
///
/// The part states the box it displays; the bitmap in the cache is the same for every box
/// (`CoverProcessor`), so opening a gallery from any list finds its cover decoded, which the
/// zoom transition needs. A cover already in memory is drawn in the view's first frame; any
/// other is asked for through `CoverLoads`, which joins the views that ask for one cover at the
/// same time into one load, so a cover shown twice at once (a list under its Continue shelf,
/// two piles) is decoded once. Originals go to the disk cache and the decoded bitmap to the
/// memory cache. The load is cancelled when the view disappears.
///
/// While the image is on its way the box shows `placeholder`, a flat fill (the look's `fill2`
/// unless the part passes another, or `.clear` to let its own tile show), and nothing spins. A
/// cover that could not be loaded shows a photo symbol on the look's surface, with
/// `failureCaption` under it when the part gives one. Decorative to VoiceOver: label the
/// containing cell.
struct CoverImage: View {
    private enum Sizing {
        case fixed(CGSize)
        case aspect(CGFloat)
        case filling
    }

    private let url: URL?
    private let sizing: Sizing
    private let contentMode: SwiftUI.ContentMode
    private let cornerRadius: CGFloat
    private let placeholder: Color?
    private let failureCaption: String?
    @Environment(\.look) private var look

    /// A fixed box, such as a row's cover. `.fill` covers and clips it; `.fit` letterboxes
    /// inside it with the corners on the image (v3's row cover).
    init(
        url: URL?, size: CGSize, contentMode: SwiftUI.ContentMode = .fill,
        cornerRadius: CGFloat = Tokens.Radius.image, placeholder: Color? = nil, failureCaption: String? = nil
    ) {
        self.url = url
        sizing = .fixed(size)
        self.contentMode = contentMode
        self.cornerRadius = cornerRadius
        self.placeholder = placeholder
        self.failureCaption = failureCaption
    }

    /// Fills the proposed width at `aspectRatio` (width / height), such as a grid cell, and
    /// covers that box.
    init(
        url: URL?, aspectRatio: CGFloat = Tokens.Aspect.cover, cornerRadius: CGFloat = Tokens.Radius.image,
        placeholder: Color? = nil, failureCaption: String? = nil
    ) {
        self.url = url
        sizing = .aspect(aspectRatio)
        contentMode = .fill
        self.cornerRadius = cornerRadius
        self.placeholder = placeholder
        self.failureCaption = failureCaption
    }

    /// Covers whatever box it is given, such as an overlay on a cell's own tile.
    init(url: URL?, fillingCornerRadius cornerRadius: CGFloat, placeholder: Color? = nil, failureCaption: String? = nil) {
        self.url = url
        sizing = .filling
        contentMode = .fill
        self.cornerRadius = cornerRadius
        self.placeholder = placeholder
        self.failureCaption = failureCaption
    }

    /// The options a list's prefetcher uses, so a prefetched cover is the entry `CoverImage`
    /// finds (`ImagePrefetcher(urls:options:)`).
    static let prefetchOptions: KingfisherOptionsInfo = CoverLoads.options

    var body: some View {
        content
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var content: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        switch sizing {
        case .fixed(let size) where contentMode == .fit:
            // Each layer has the corners: the letterboxed image its own.
            bitmap
                .frame(width: size.width, height: size.height)
        case .fixed(let size):
            Color.clear
                .frame(width: size.width, height: size.height)
                .overlay { bitmap }
                .clipShape(shape)
                .contentShape(shape)
        case .aspect(let ratio):
            Color.clear
                .aspectRatio(ratio, contentMode: .fit)
                .overlay { bitmap }
                .clipShape(shape)
                .contentShape(shape)
        case .filling:
            Color.clear
                .overlay { bitmap }
                .clipShape(shape)
                .contentShape(shape)
        }
    }

    private var bitmap: CoverBitmap {
        CoverBitmap(
            url: url, contentMode: contentMode, layerCorners: contentMode == .fit ? cornerRadius : nil,
            placeholder: placeholder ?? look.fill2, failureCaption: failureCaption, look: look
        )
    }
}

/// The image of one cover, its placeholder and its failure. Holds the bitmap that arrived for
/// its URL; a bitmap already in memory is not held but looked up, so it is drawn at once.
private struct CoverBitmap: View {
    let url: URL?
    let contentMode: SwiftUI.ContentMode
    /// The corners of each layer, where the box itself has none (a letterboxed image).
    let layerCorners: CGFloat?
    let placeholder: Color
    let failureCaption: String?
    let look: Look

    /// The bitmap a load brought, with the URL it is for.
    @State private var arrived: Arrived?
    /// The URL whose load failed.
    @State private var failedURL: URL?
    /// The arrived bitmap has faded in.
    @State private var isShown = false

    private struct Arrived {
        let url: URL
        let image: UIImage
    }

    var body: some View {
        let held = arrived.flatMap { $0.url == url ? $0.image : nil }
        let image = held ?? CoverLoads.memoryImage(for: url)
        // A bitmap found in memory is there from the first frame; one that arrived fades in.
        let isVisible = image != nil && (held == nil || isShown)
        ZStack {
            placeholder
                .modifier(CoverLayerCorners(radius: layerCorners))
                .opacity(isVisible ? 0 : 1)
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .modifier(CoverLayerCorners(radius: layerCorners))
                    .opacity(isVisible ? 1 : 0)
            } else if url == nil || failedURL == url {
                CoverFailure(caption: failureCaption, look: look)
                    .modifier(CoverLayerCorners(radius: layerCorners))
            }
        }
        .task(id: url) { await load() }
    }

    private func load() async {
        guard let url, arrived?.url != url, CoverLoads.memoryImage(for: url) == nil else { return }
        isShown = false
        switch await CoverLoads.shared.load(url) {
        case .image(let image):
            arrived = Arrived(url: url, image: image)
            withAnimation(.easeOut(duration: Tokens.Duration.imageFade)) { isShown = true }
        case .failed:
            failedURL = url
        case .cancelled:
            break
        }
    }
}

/// Rounds a layer of a letterboxed cover; a cover that fills its box is rounded as a whole.
private struct CoverLayerCorners: ViewModifier {
    let radius: CGFloat?

    func body(content: Content) -> some View {
        if let radius {
            content.clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        } else {
            content
        }
    }
}

/// A cover that could not be loaded: a photo symbol on the look's surface, and a caption under
/// it when the part gives one ("Cover not saved").
private struct CoverFailure: View {
    let caption: String?
    let look: Look

    var body: some View {
        look.surface
            .overlay {
                if let caption {
                    VStack(spacing: 4) {
                        Image(systemName: "photo")
                            .font(.body)
                        Text(caption)
                            .font(.caption2)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                    }
                    .padding(4)
                } else {
                    Image(systemName: "photo")
                        .font(.title3)
                }
            }
            .foregroundStyle(look.tertiaryLabel)
    }
}
