import EhCore
import EhFeatures
import EhModels
import SwiftUI

/// What the shell presents over the browsing UI, under either bar: the Settings sheet, the
/// gallery sheet for links opened from outside the app, the daily greeting, the reader
/// opened from Continue, the offer after install, and the link HUD. Attached above the bar's
/// switch, so none of them goes away when the bar or a design changes behind it.
///
/// Only the topmost presenter can present, so each sheet attaches what may arrive while it
/// is up: a link's gallery over Settings, the greeting over either.
struct ShellPresentations: ViewModifier {
    let model: AppModel

    func body(content: Content) -> some View {
        let router = model.router
        content
            .sheet(isPresented: isSettingsPresented) {
                SettingsSheet(router: router)
                    .modifier(GallerySheet(router: router, isActive: true))
                    .newDawnSheet(router: router, isTopmost: router.presentedGallery == nil)
            }
            .modifier(GallerySheet(router: router, isActive: !router.isSettingsPresented))
            .newDawnSheet(
                router: router, isTopmost: router.presentedGallery == nil && !router.isSettingsPresented
            )
            // Continue, from the tab bar's accessory or a first screen. `readerCover` replaces
            // this line when the reader's shared layer is merged.
            .fullScreenCover(item: reading) { request in
                ReaderScreen(gallery: request.gallery, initialPage: request.page)
            }
            .sheet(isPresented: offer) {
                ExperienceOfferSlot(router: router)
            }
            .hud(linkHUD)
            .sensoryFeedback(.impact(weight: .light), trigger: router.presentedGallery?.gid) { _, new in new != nil }
            .task(id: model.links.request) { await model.links.handleRequest() }
            .task(id: model.activationRequest) { await model.performActivationWork() }
    }

    private var isSettingsPresented: Binding<Bool> {
        Binding(
            get: { model.router.isSettingsPresented },
            set: { if !$0 { model.router.dismissSettings() } }
        )
    }

    private var reading: Binding<ReadingRequest?> {
        Binding(get: { model.router.reading }, set: { model.router.reading = $0 })
    }

    /// The router's queue rule: unlocked, and neither the greeting nor the gallery sheet up.
    private var offer: Binding<Bool> {
        Binding(
            get: { model.router.showsOffer(isUnlocked: !model.lock.isLocked) },
            set: { if !$0 { model.router.offer = false } }
        )
    }

    /// Progress of a link being opened; the error HUD clears itself.
    private var linkHUD: Binding<HUDConfiguration?> {
        Binding(
            get: {
                switch model.links.progress {
                case .loading: .loading
                case .failed: .error
                case nil: nil
                }
            },
            set: { if $0 == nil { model.links.progress = nil } }
        )
    }
}

/// Settings: a sheet with its own stack, opened from the account button, the place menu and
/// the sign-in prompts (`AppRouter.presentSettings`).
private struct SettingsSheet: View {
    let router: AppRouter

    var body: some View {
        RoutedStack(router: router.settings) {
            SettingsScreen()
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        SheetCloseButton { router.dismissSettings() }
                    }
                }
        }
        .pushesGalleries(on: router.settings)
    }
}

/// The gallery opened from a deep link, a clipboard link or the share extension: always a
/// sheet with its own stack and its own chrome host for the page's dock, never a side pane.
private struct GallerySheet: ViewModifier {
    let router: AppRouter
    /// Whether this is the topmost presenter.
    let isActive: Bool

    @Environment(\.chrome) private var chrome

    func body(content: Content) -> some View {
        content.sheet(item: presentedGallery) { gallery in
            BottomChrome(router: router.presented) {
                RoutedStack(router: router.presented) {
                    // The link's target (an image page or a comment) is honoured once.
                    GalleryPage(
                        gallery: gallery,
                        intent: router.takePresentedGalleryTarget(for: gallery.gid).map(DetailIntent.init)
                    )
                }
            }
            .pushesGalleries(on: router.presented)
            .environment(\.chrome, chrome.presented(isSheet: true))
            // The page in this sheet may receive the greeting; only the topmost presenter
            // can show it.
            .newDawnSheet(router: router, isTopmost: true)
        }
    }

    private var presentedGallery: Binding<Gallery?> {
        Binding(
            get: { isActive ? router.presentedGallery : nil },
            set: { if $0 == nil, isActive { router.dismissPresentedGallery() } }
        )
    }
}
