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
    /// Where the content ends and where the open pane is, in the window: the pane lies over the
    /// content when the system has not made room for it (iOS 18 in portrait).
    @State private var contentEnd: CGFloat = 0
    @State private var paneSpan: ClosedRange<CGFloat>?
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.chrome) private var chrome

    private var hasRoom: Bool {
        sizeClass == .regular && width >= GalleryPlacement.minimumContainerWidth
    }

    private var opensInPane: Bool { placement == .sidePane && hasRoom }

    private var paneWidth: CGFloat { design.sidePaneWidth(in: width) }

    /// The open pane lies over the content: the system dims the content, and its first tap only
    /// closes the pane.
    ///
    /// Only a pane wholly inside the content's span counts: one that slides in beside the
    /// content passes through positions where it overlaps the content's old edge.
    private var coversContent: Bool {
        guard isPresented.wrappedValue, let paneSpan else { return false }
        return paneSpan.lowerBound < contentEnd - 1 && paneSpan.upperBound <= contentEnd + 1
    }

    func body(content: Content) -> some View {
        content
            .environment(\.openGallery, GalleryOpener(router: router, inSidePane: opensInPane))
            .environment(\.sidePaneWidth, isPresented.wrappedValue ? paneWidth : 0)
            .environment(\.isUnderSidePane, coversContent)
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).maxX } action: { contentEnd = $0 }
            // Forgotten when the pane closes, not when its view goes: on iOS 18 the pane's view is
            // laid out before it opens, and one view can go after another has measured.
            .onChange(of: isPresented.wrappedValue) { _, isOpen in
                if !isOpen { paneSpan = nil }
            }
            .inspector(isPresented: isPresented) {
                SidePaneStack(router: router)
                    .environment(\.chrome, chrome.presented(isSidePane: true))
                    .onGeometryChange(for: ClosedRange<CGFloat>.self) { geometry in
                        let frame = geometry.frame(in: .global)
                        return frame.minX...max(frame.minX, frame.maxX)
                    } action: { paneSpan = $0 }
                    // Last, on the pane's root. One modifier with a computed value: switching
                    // between width modifiers recreates the pane's page.
                    .inspectorColumnWidth(paneWidth)
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

extension EnvironmentValues {
    /// How wide the side pane around this content is while it is open, zero while it is
    /// closed. It changes in the update that opens the pane, before the pane has taken its
    /// room: Ledger's split view hides its Index then if the room left is too small.
    @Entry var sidePaneWidth: CGFloat = 0

    /// The open side pane lies over this content instead of beside it, and the system dims the
    /// content: its bottom chrome fades as it does under anything drawn over the stack.
    @Entry var isUnderSidePane = false
}

extension View {
    /// Calls `action` with the side pane's width when it opens or closes (zero).
    func onSidePaneWidthChange(_ action: @escaping (CGFloat) -> Void) -> some View {
        modifier(SidePaneWidthChange(action: action))
    }
}

private struct SidePaneWidthChange: ViewModifier {
    let action: (CGFloat) -> Void
    @Environment(\.sidePaneWidth) private var width

    func body(content: Content) -> some View {
        content.onChange(of: width) { _, new in action(new) }
    }
}
