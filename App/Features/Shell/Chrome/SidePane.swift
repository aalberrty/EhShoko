import EhFeatures
import EhModels
import SwiftUI

/// The trailing side pane of a browse stack (`Design/designs/README.md` section 5.8, rule 3;
/// `spikes/S5.md` sections 1, 2 and 6): an `inspector` holding the gallery the stack's router
/// opened beside its list, with a stack and a bottom chrome host of its own.
///
/// It goes around the list column's `BottomChrome`, or around Ledger's whole split view,
/// never on a stack inside either: the command bar then stays centred in the list area and
/// the pane is a full-height column.
struct SidePane: ViewModifier {
    let router: StackRouter
    let design: DesignStyle
    let placement: GalleryPlacement

    /// The container's width, measured on the view that carries the inspector: it does not
    /// change when the pane opens. Zero until the first layout, so a container that has just
    /// been built never presents a pane during its first layout, which UIKit asserts on.
    @State private var width: CGFloat = 0
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.chrome) private var chrome

    private var hasRoom: Bool {
        sizeClass == .regular && width >= GalleryPlacement.minimumContainerWidth
    }

    private var opensInPane: Bool { placement == .sidePane && hasRoom }

    func body(content: Content) -> some View {
        content
            .environment(\.openGallery, GalleryOpener(router: router, inSidePane: opensInPane))
            .inspector(isPresented: isPresented) {
                SidePaneStack(router: router)
                    .environment(\.chrome, chrome.presented(isSidePane: true))
                    // One modifier with a computed value: switching between width modifiers
                    // recreates the pane's page.
                    .inspectorColumnWidth(design.sidePaneWidth(in: width))
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            .onChange(of: PaneState(hasGallery: router.sideGallery != nil, allows: opensInPane, isMeasured: width > 0)) {
                _, state in
                // A pane that lost its place (a Split View drag, a window resize, a compact
                // width, a gallery design that pushes) moves onto the stack with its screens.
                if state.isMeasured, state.hasGallery, !state.allows {
                    router.moveSidePaneOntoStack()
                }
            }
    }

    private var isPresented: Binding<Bool> {
        Binding(
            get: { router.sideGallery != nil && opensInPane },
            // SwiftUI writes `true` once at launch; only `false` (the system's own dismissal)
            // means anything.
            set: { if !$0 { router.closeSidePane() } }
        )
    }

    nonisolated private struct PaneState: Equatable {
        let hasGallery: Bool
        let allows: Bool
        let isMeasured: Bool
    }
}

/// The pane's content: the gallery page on the pane's own stack, with its own chrome host
/// for the page's dock and its child screens'.
private struct SidePaneStack: View {
    let router: StackRouter

    var body: some View {
        if let gallery = router.sideGallery {
            let side = router.side
            BottomChrome(router: side) {
                RoutedStack(router: side) {
                    GalleryPage(gallery: gallery, intent: router.sideIntent)
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                SheetCloseButton { router.closeSidePane() }
                            }
                        }
                        // Another gallery in the pane is another page, with its own model.
                        .id(gallery.gid)
                }
            }
            .pushesGalleries(on: side)
        }
    }
}
