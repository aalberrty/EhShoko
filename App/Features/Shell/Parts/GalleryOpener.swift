import EhCore
import EhFeatures
import EhModels
import SwiftUI

/// Opens a gallery the right way for where the caller is (`Design/designs/README.md`
/// section 5.4): pushed onto the stack, or, on regular width for the gallery designs that ask
/// for it, in the stack's side pane.
///
/// A part reads `\.openGallery` and calls it from a row's tap handler at the list level,
/// never from a cell, and never pushes `Route.detail` itself.
nonisolated struct GalleryOpener {
    fileprivate let router: StackRouter?
    fileprivate let usesSidePane: Bool

    /// `origin` says which kind of cover was tapped where a screen can show one gallery
    /// twice; that cover marks itself with `galleryZoomSource(_:from:)`.
    @MainActor
    func callAsFunction(_ gallery: Gallery, intent: DetailIntent? = nil, from origin: GalleryOrigin = .list) {
        router?.open(gallery, intent: intent, origin: origin, inSidePane: usesSidePane)
    }
}

extension GalleryOrigin {
    /// The id of the zoom between a cover of this kind and the gallery page. A list's covers
    /// keep the gid alone, the id every list design's rows already give their cover.
    func zoomID(gid: String) -> AnyHashable {
        switch self {
        case .list: AnyHashable(gid)
        case .coverShelf, .recentlySeen: AnyHashable(GalleryZoomID(gid: gid, origin: self))
        }
    }
}

nonisolated private struct GalleryZoomID: Hashable {
    let gid: String
    let origin: GalleryOrigin
}

extension View {
    /// Marks a cover outside a list as where the zoom into its gallery starts and ends, for a
    /// gallery opened with `openGallery(_:from:)` from the same `origin`.
    func galleryZoomSource(_ gid: String, from origin: GalleryOrigin) -> some View {
        zoomSource(origin.zoomID(gid: gid))
    }
}

extension EnvironmentValues {
    /// Set by the shell on every stack. Outside a stack it does nothing.
    @Entry var openGallery = GalleryOpener(router: nil, usesSidePane: false)
}

/// Where a gallery design wants its page on regular width. The page itself never presents
/// itself: it only has this preference, and the shell acts on it.
nonisolated enum GalleryPlacement: Equatable, Sendable {
    /// Pushed on every width (Shelf, which lays itself out in two columns when wide).
    case pushed
    /// In the trailing side pane, `width(container)` wide.
    case sidePane

    init(_ design: DesignStyle) {
        self = design == .shelf ? .pushed : .sidePane
    }

    /// The narrowest stack that still shows a pane beside its list.
    static let minimumContainerWidth: CGFloat = 900
}

extension DesignStyle {
    /// The side pane's width for this gallery design in a container `container` wide: Wall's
    /// card is 372 pt, Ledger's page 44% of the width between 420 and 520 pt. The system
    /// honours any width, so the limits are enforced here (`spikes/S5.md` section 1.3).
    nonisolated func sidePaneWidth(in container: CGFloat) -> CGFloat {
        switch self {
        case .ledger: min(max(container * 0.44, 420), 520)
        case .shelf, .wall: 372
        }
    }
}

extension View {
    /// Around the bottom chrome's host of a browse stack: galleries opened from the stack go
    /// where the gallery design wants them, and the side pane is attached here.
    ///
    /// This is the gallery part's second switch point: `GalleryPage` decides what a gallery
    /// page is, this decides where it opens. Both read `designGallery`, nothing else does.
    func opensGalleries(on router: StackRouter) -> some View {
        modifier(GalleryOpening(router: router))
    }

    /// A stack that only pushes: the side pane's own stack, the gallery sheet, Settings.
    func pushesGalleries(on router: StackRouter) -> some View {
        environment(\.openGallery, GalleryOpener(router: router, usesSidePane: false))
    }
}

private struct GalleryOpening: ViewModifier {
    let router: StackRouter
    @Environment(SettingsStore.self) private var settings

    func body(content: Content) -> some View {
        let design = settings.designGallery
        content.modifier(SidePane(router: router, design: design, placement: GalleryPlacement(design)))
    }
}

extension GalleryOpener {
    /// For `SidePane`, which knows whether its container has room for a pane.
    init(router: StackRouter, inSidePane: Bool) {
        self.init(router: router, usesSidePane: inSidePane)
    }
}
