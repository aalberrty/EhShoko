import SwiftUI

// The zoom from a cover into its gallery page (iOS 18 API, the same on iOS 26). The shell puts
// one namespace per stack into the environment; a part marks its covers as sources and the
// gallery page as the destination, and never creates a namespace of its own.

extension EnvironmentValues {
    /// The stack's zoom namespace, set by the shell (`RoutedStack`). `nil` outside a stack,
    /// where the zoom helpers do nothing.
    @Entry var zoomNamespace: Namespace.ID?
}

extension View {
    /// Marks this view (a cover) as where the zoom to the screen with the same `id` starts.
    func zoomSource(_ id: some Hashable) -> some View {
        modifier(ZoomSource(id: AnyHashable(id)))
    }

    /// Marks this screen as the zoom's destination from the source with the same `id`.
    func zoomDestination(_ id: some Hashable) -> some View {
        modifier(ZoomDestination(id: AnyHashable(id)))
    }
}

private struct ZoomSource: ViewModifier {
    let id: AnyHashable
    @Environment(\.zoomNamespace) private var namespace

    func body(content: Content) -> some View {
        if let namespace {
            content.matchedTransitionSource(id: id, in: namespace)
        } else {
            content
        }
    }
}

private struct ZoomDestination: ViewModifier {
    let id: AnyHashable
    @Environment(\.zoomNamespace) private var namespace

    func body(content: Content) -> some View {
        if let namespace {
            content.navigationTransition(.zoom(sourceID: id, in: namespace))
        } else {
            content
        }
    }
}
