import EhCore
import EhFeatures
import EhModels
import SwiftUI

// Shelf's gallery page and the screens opened from it (`Design/designs/shelf.md` section 4).
//
// `GalleryPage` and `GalleryChildScreen` (Shell/Parts) call the three entry types:
// `ShelfGalleryView`, `ShelfGalleryChildView` and `ShelfGallerySheet`. The load, the pushed
// children, the sheets and the reader are `GalleryPage`'s, around every design: this page draws
// the model, declares its dock and sets `model.destination`; it presents nothing itself.

/// The page: pushed on every width, or the root of the side pane or the gallery sheet when it
/// is opened there. From 700 pt wide it is laid out in two columns.
struct ShelfGalleryView: View {
    let model: GalleryDetailModel

    @Environment(StackRouter.self) private var stack: StackRouter?
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.look) private var look
    @State private var width: CGFloat?
    @State private var hud: HUDConfiguration?
    @State private var asksToSignIn = false

    var body: some View {
        ScrollView {
            if isWide {
                wide
            } else {
                compact
            }
        }
        .background(look.background)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ShelfGalleryToolbar(model: model) { keyword in stack?.push(.search(keyword: keyword)) }
        }
        .shelfGalleryDock(model, signIn: signIn)
        .hud($hud)
        .galleryFavoriteHUD(model, hud: $hud)
        .gallerySignInAlert(isPresented: $asksToSignIn)
    }

    /// Before the first layout the size class decides, so an iPad opens in two columns.
    private var isWide: Bool {
        guard let width else { return sizeClass == .regular }
        return width >= ShelfGalleryLayout.twoColumnWidth
    }

    private var compact: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            header
            ShelfGalleryMain(model: model, signIn: signIn)
            ShelfGalleryMore(model: model)
        }
        .padding(.top, Tokens.Spacing.small)
        .padding(.bottom, Tokens.Spacing.xLarge)
    }

    /// Header, figures, actions and previews on the left; tags and comments on the right.
    private var wide: some View {
        HStack(alignment: .top, spacing: Tokens.Spacing.small) {
            VStack(alignment: .leading, spacing: 0) {
                header
                ShelfGalleryMain(model: model, signIn: signIn)
            }
            .frame(maxWidth: .infinity, alignment: .top)
            ShelfGalleryMore(model: model)
                .frame(maxWidth: .infinity, alignment: .top)
                .padding(.top, -18)
        }
        .padding(.horizontal, Tokens.Spacing.small)
        .padding(.top, Tokens.Spacing.small)
        .padding(.bottom, Tokens.Spacing.xLarge)
    }

    private var header: some View {
        ShelfGalleryHeader(model: model) { hud = .copiedToClipboard }
    }

    private func signIn() {
        asksToSignIn = true
    }
}

/// What follows the header in the first column: the figures, the actions and the previews once
/// the page is there; until then placeholders; the error view when it failed. A saved page
/// shown because the fetch failed has a line saying so.
private struct ShelfGalleryMain: View {
    let model: GalleryDetailModel
    let signIn: () -> Void

    var body: some View {
        if let failure = model.loadingState.failed, model.detail == nil || !failure.isRetryable {
            // In the scrolling page: a filled Retry, not glass.
            ErrorStateView(error: failure, retry: failure.isRetryable ? { model.refetch() } : nil)
                .statusActionForm(.filled)
                .padding(.top, Tokens.Spacing.xxLarge)
        } else if let detail = model.detail {
            if let failure = model.loadingState.failed {
                ListOfflineBanner(form: .line(banner(for: failure)), retry: model.refetch)
                    .padding(.horizontal, Tokens.Spacing.large)
                    .padding(.top, Tokens.Spacing.medium)
            }
            ShelfGalleryFigures(
                detail: detail, readingProgress: model.readingProgress, isTranslated: Self.isTranslated(model)
            )
            .padding(.top, Tokens.Spacing.medium)
            ShelfGalleryActions(model: model, signIn: signIn)
            ShelfGalleryPreviews(model: model)
        } else {
            ShelfGalleryPlaceholder()
        }
    }

    private func banner(for failure: AppError) -> String {
        failure == .networkingFailed ? L10n.Localizable.Gallery.offline : failure.headline ?? L10n.Localizable.Gallery.offline
    }

    /// Whether the gallery carries the "translated" language tag.
    private static func isTranslated(_ model: GalleryDetailModel) -> Bool {
        let tags = model.tagRows.isEmpty ? model.gallery.tags : model.tagRows.map(\.tag)
        return tags.contains { tag in
            tag.namespace == .language && tag.contents.contains { $0.text == "translated" }
        }
    }
}

/// The tags and the comments: below the first column on a phone, beside it when wide. Nothing
/// until the page is there.
private struct ShelfGalleryMore: View {
    let model: GalleryDetailModel

    var body: some View {
        if model.detail != nil, model.loadingState.failed?.isRetryable != false {
            ShelfGalleryTags(model: model)
            ShelfGalleryComments(model: model)
        }
    }
}
