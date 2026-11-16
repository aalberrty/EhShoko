import EhCore
import EhFeatures
import EhModels
import EhNetworking
import SwiftUI

/// What the shell presents over the browsing UI, under either bar: the Settings sheet, the
/// gallery sheet for links opened from outside the app, the daily greeting, the reader
/// opened from Continue, the offer after install, and the link HUD. Attached above the bar's
/// switch, so none of them goes away when the bar or a design changes behind it.
///
/// Only the topmost presenter can present, so each sheet attaches what may arrive while it
/// is up: a link's gallery over Settings, Settings over a link's gallery (opened from its
/// page), the greeting over either. Whichever came second is above (`ShellSheetOrder`).
///
/// It also gives every screen below it two openers: `\.openContinueReader`, and `\.openURL`
/// for the app's own links (`ehshoko://`, which the Index's paste button and the search
/// surface's copied-link offer hand it), opened here as a shared link is, without a trip
/// through the system.
struct ShellPresentations: ViewModifier {
    let model: AppModel
    /// The bar in use, which says where Continue is and so what the reader zooms out of.
    let bar: BarStyle

    /// The gallery of the reader last opened from Continue.
    @State private var lastRead: Gallery?
    /// The Continue control that opened that reader, when it said.
    @State private var continueOrigin = ContinueReaderOrigin()
    /// Which of Settings and the gallery sheet was above the other at the last update.
    @State private var sheetOrder = ShellSheetOrder()

    func body(content: Content) -> some View {
        let router = model.router
        let order = sheetOrder.next(isSettingsUp: router.isSettingsPresented, isGalleryUp: router.presentedGallery != nil)
        content
            .sheet(isPresented: settings(isAtRoot: order.settingsAtRoot)) {
                SettingsSheet(router: router)
                    .modifier(GallerySheet(router: router, isActive: true))
                    .newDawnSheet(router: router, isTopmost: router.presentedGallery == nil)
            }
            .modifier(GallerySheet(router: router, isActive: order.galleryAtRoot, holdsSettings: order.settingsOverGallery))
            .newDawnSheet(
                router: router, isTopmost: router.presentedGallery == nil && !router.isSettingsPresented
            )
            .onChange(of: order) { _, order in sheetOrder = order }
            .readerCover(item: reading, source: continueSource, onExit: leaveReader, onDismiss: continueOrigin.clear)
            .onChange(of: router.reading) { _, request in
                if let request { lastRead = request.gallery }
            }
            .modifier(ExperienceOfferSlot(offer: model.experienceOffer, router: router))
            .hud(linkHUD)
            .sensoryFeedback(.impact(weight: .light), trigger: router.presentedGallery?.gid) { _, new in new != nil }
            .task(id: model.links.request) { await model.links.handleRequest() }
            .task(id: model.activationRequest) { await model.performActivationWork() }
            // Outside the sheets, so the screens in them have both too.
            .environment(\.openContinueReader, ContinueReaderOpener(router: router, origin: continueOrigin))
            .environment(\.openURL, OpenURLAction { [links = model.links] url in
                guard url.scheme == EhURL.appScheme else { return .systemAction }
                links.open(url)
                return .handled
            })
    }

    /// What the reader opened from Continue zooms out of: the control that said it opened it
    /// (`\.openContinueReader`), else under `tabs` the bar's accessory and under `command` the
    /// first screen's card or banner.
    private func continueSource(_ request: ReadingRequest) -> ReaderSourceID {
        let gid = request.gallery.gid
        switch continueOrigin.control(for: gid) ?? (bar == .tabs ? .bar : .card) {
        case .bar: return .continueBar(gid: gid)
        case .card: return .continueCard(gid: gid)
        }
    }

    /// Where the reader's closing page leads, once the reader opened from Continue has
    /// closed: onto the stack the user is on.
    private func leaveReader(_ exit: ReaderExit) {
        let router = model.router
        switch exit {
        case .gallery:
            if let lastRead { router.selectedStack.push(.detail(lastRead)) }
        case .comments:
            if let lastRead { router.selectedStack.push(.detail(lastRead, intent: .comments(scrollTo: nil))) }
        case .search(let keyword):
            router.selectedStack.push(.search(keyword: keyword))
        case .signIn:
            router.presentSignIn()
        }
    }

    /// Settings presented by the root: up, and not over the gallery sheet.
    private func settings(isAtRoot: Bool) -> Binding<Bool> {
        Binding(
            get: { isAtRoot },
            set: { if !$0, isAtRoot { model.router.dismissSettings() } }
        )
    }

    private var reading: Binding<ReadingRequest?> {
        Binding(get: { model.router.reading }, set: { model.router.reading = $0 })
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
/// the sign-in prompts (`AppRouter.presentSettings`, `presentSignIn`). Done, the system's
/// confirm button at the top trailing corner, closes it.
struct SettingsSheet: View {
    let router: AppRouter

    /// The look the sheet's screens were built in.
    @State private var builtLook: Look?
    @Environment(\.look) private var look

    var body: some View {
        RoutedStack(router: router.settings) {
            SettingsScreen()
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        SheetConfirmButton { router.dismissSettings() }
                    }
                }
        }
        .pushesGalleries(on: router.settings)
        // A list's rows keep the separator colour they were first drawn with, so after a
        // change of look the screens are built again, on the same path. Not in the update
        // that changed it: what changed it (a preset tile, the wizard's Apply) still reacts
        // to its own change with a haptic and, for the wizard, by leaving.
        .id(builtLook ?? look)
        .task(id: look) {
            guard let builtLook, builtLook != look else {
                builtLook = look
                return
            }
            try? await Task.sleep(for: .seconds(0.8))
            if !Task.isCancelled { self.builtLook = look }
        }
    }
}

extension AppRouter {
    /// Opens sign-in: the Settings sheet at Settings › Sign in, Back leading to the page with
    /// the account card. Every prompt for an account opens it this way and at once, without
    /// asking first, as the old app's Login did.
    func presentSignIn() {
        presentSettings([.settings(.login)])
    }
}
