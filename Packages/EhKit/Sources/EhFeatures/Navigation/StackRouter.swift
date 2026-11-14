import EhModels
import Observation

/// The path of one `NavigationStack`. Each stack puts its router in the SwiftUI environment,
/// so a view pushes onto the stack it lives in without knowing which tab or sheet that is.
///
/// On regular width a stack can also show a gallery in its trailing side pane, which has a
/// stack of its own for the gallery's child screens (`Design/designs/README.md` section 5.8).
@Observable
public final class StackRouter {
    public var path: [Route] = []

    /// The gallery in the side pane; `nil` when the pane is closed.
    public private(set) var sideGallery: Gallery?
    /// What the gallery in the side pane should do once it has opened.
    public private(set) var sideIntent: DetailIntent?

    @ObservationIgnored private var sideStorage: StackRouter?

    public init() {}

    public var isAtRoot: Bool { path.isEmpty }

    /// Whether the browse bar is hidden: the top screen's answer, at any depth. The root
    /// screens (first screen, lists, the library, search) all show it.
    public var hidesBrowseChrome: Bool { path.last?.hidesBrowseChrome ?? false }

    /// The side pane's own stack, created the first time a pane needs it.
    public var side: StackRouter {
        if let sideStorage { return sideStorage }
        let router = StackRouter()
        sideStorage = router
        return router
    }

    public func push(_ route: Route) {
        path.append(route)
    }

    public func pop() {
        _ = path.popLast()
    }

    public func popToRoot() {
        path.removeAll()
    }

    /// Opens a gallery: pushed onto this stack, or shown in the side pane on a fresh pane
    /// stack. The caller (`\.openGallery`) decides which from the layout and the gallery design.
    public func open(_ gallery: Gallery, intent: DetailIntent? = nil, inSidePane: Bool) {
        guard inSidePane else {
            push(.detail(gallery, intent: intent))
            return
        }
        sideStorage?.popToRoot()
        sideIntent = intent
        sideGallery = gallery
    }

    public func closeSidePane() {
        sideGallery = nil
        sideIntent = nil
        sideStorage?.popToRoot()
    }
}
