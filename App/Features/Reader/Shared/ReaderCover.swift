import EhFeatures
import EhModels
import SwiftUI

// How the reader is presented (`Design/designs/README.md` section 5.5, spike S4): whoever
// opens it, a gallery page, a list or the shell, presents it with `readerCover`, and it zooms
// out of the control that opened it when that control marked itself with `readerSource`.

/// The control a reader zooms out of and back into. One zoom namespace from the root serves
/// every presenter, because the dock and the tab accessory sit outside the stacks, so an id
/// must be unique across the app: each names its place and its gallery.
enum ReaderSourceID: Hashable, Sendable {
    /// The gallery page's Read pill in the dock.
    case dock(gid: String)
    /// The Continue bar or accessory.
    case continueBar(gid: String)
    /// A Continue card on a first screen.
    case continueCard(gid: String)
    /// A row's cover in a list (Read from the long-press menu).
    case row(gid: String)
    /// A page's preview on the gallery page or in the previews grid.
    case preview(gid: String, page: Int)
}

/// Where the closing page sends the reader (`Design/designs/closing-page.md`). The presenter
/// closes the reader and goes there, so the reader never navigates by itself.
enum ReaderExit: Hashable, Sendable {
    case gallery
    case comments
    case search(keyword: String)
    case signIn
}

/// Leaves the reader for `ReaderExit`, through its presenter. Read from the environment by
/// what is shown inside the reader (the closing page).
struct ReaderExitAction {
    fileprivate let action: (ReaderExit) -> Void

    func callAsFunction(_ exit: ReaderExit) {
        action(exit)
    }
}

extension EnvironmentValues {
    /// Set by `readerCover` on the reader it presents; `nil` elsewhere.
    @Entry var readerExit: ReaderExitAction?
}

extension View {
    /// Marks this view, the content of a control that opens the reader, as where the reader
    /// zooms out of. On iOS 26 a marker around glass does nothing, so it goes on the label,
    /// **inside** the glass: `Text(…).readerSource(.dock(gid: gid)).glassSurface(in: .capsule)`.
    /// Never on an empty shape (spike S4).
    func readerSource(_ id: ReaderSourceID) -> some View {
        modifier(ReaderSourceMarker(id: id))
    }

    /// Presents the reader for `item` over the whole screen.
    ///
    /// - Parameters:
    ///   - detail: the gallery page's model, when a gallery page presents it.
    ///   - source: the control the reader zooms out of, asked when it opens. `nil`, or no
    ///     namespace in the environment, gives the system's cover transition; the choice
    ///     cannot be made when it closes. A control that has gone while reading is zoomed back
    ///     to where it was.
    ///   - onExit: where to go after the closing page closed the reader.
    ///   - onDismiss: after the reader went away, however it was closed: a list refreshes its
    ///     rows' reading progress here.
    func readerCover(
        item: Binding<ReadingRequest?>,
        detail: GalleryDetailModel? = nil,
        source: @escaping (ReadingRequest) -> ReaderSourceID? = { _ in nil },
        onExit: @escaping (ReaderExit) -> Void = { _ in },
        onDismiss: (() -> Void)? = nil
    ) -> some View {
        modifier(ReaderCover(item: item, detail: detail, source: source, onExit: onExit, onDismiss: onDismiss))
    }

    /// Presents the reader a gallery page asked for in its full-screen destination.
    func readerCover(
        destination: Binding<DetailDestination?>,
        of model: GalleryDetailModel,
        source: ReaderSourceID? = nil,
        onExit: @escaping (ReaderExit) -> Void = { _ in },
        onDismiss: (() -> Void)? = nil
    ) -> some View {
        let item = Binding<ReadingRequest?>(
            get: {
                guard case .reader(let page)? = destination.wrappedValue else { return nil }
                return ReadingRequest(gallery: model.gallery, page: page)
            },
            set: { request in
                if request == nil { destination.wrappedValue = nil }
            }
        )
        return readerCover(item: item, detail: model, source: { _ in source }, onExit: onExit, onDismiss: onDismiss)
    }
}

private struct ReaderSourceMarker: ViewModifier {
    let id: ReaderSourceID
    @Environment(\.zoomNamespace) private var namespace

    func body(content: Content) -> some View {
        if let namespace {
            content.matchedTransitionSource(id: id, in: namespace)
        } else {
            content
        }
    }
}

private struct ReaderCover: ViewModifier {
    @Binding var item: ReadingRequest?
    let detail: GalleryDetailModel?
    let source: (ReadingRequest) -> ReaderSourceID?
    let onExit: (ReaderExit) -> Void
    let onDismiss: (() -> Void)?

    @Environment(\.zoomNamespace) private var namespace

    func body(content: Content) -> some View {
        content.fullScreenCover(item: $item, onDismiss: onDismiss) { request in
            ReaderScreen(gallery: request.gallery, initialPage: request.page, detail: detail?.detail)
                .modifier(ReaderZoom(sourceID: source(request), namespace: namespace))
                .environment(\.readerExit, ReaderExitAction { exit in
                    item = nil
                    onExit(exit)
                })
        }
    }
}

private struct ReaderZoom: ViewModifier {
    let sourceID: ReaderSourceID?
    let namespace: Namespace.ID?

    func body(content: Content) -> some View {
        if let sourceID, let namespace {
            content
                .navigationTransition(.zoom(sourceID: sourceID, in: namespace))
                // The zoom's pull-down, pinch and edge-swipe dismissals would take the page's
                // own drags and pinches (spike S4). Leaving is Close's job.
                .interactiveDismissDisabled()
        } else {
            content
        }
    }
}
