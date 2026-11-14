import EhFeatures
import SwiftUI

/// A `NavigationStack` bound to a `StackRouter`, with what every stack needs
/// (`Design/designs/README.md` section 6): the route destination map, the router in every
/// screen's environment, and each screen stamped for the bottom chrome's host.
///
/// It is not the host: `BottomChrome` goes around it, or around the split view that holds it,
/// and the side pane around that (`StackHost`).
struct RoutedStack<Root: View>: View {
    @Bindable var router: StackRouter
    @ViewBuilder var root: Root

    var body: some View {
        NavigationStack(path: $router.path) {
            root
                .stackScreen(nil, on: router)
                .navigationDestination(for: Route.self) { route in
                    RouteDestination(route: route)
                        .stackScreen(route, on: router)
                }
                .hidesTabBarOnGalleries(router)
        }
        .environment(router)
    }
}

/// The list column beside Ledger's Index on regular width (`spikes/S5.md` section 4): the
/// same router as on a phone, drawn differently. On a phone the Index is the stack's root and
/// the place's list is the first route over it; here the Index is the split view's sidebar, so
/// that first route's screen is the column's root and only the routes after it are pushed.
/// The router's path is the same in both, so nothing is converted when the width changes.
struct PlaceRootedStack<Fallback: View>: View {
    let router: StackRouter
    /// The root while no place is on the path: the list to open on.
    @ViewBuilder var fallback: Fallback

    var body: some View {
        let base = router.path.first.flatMap { $0.isPlace ? $0 : nil }
        NavigationStack(path: pushed(over: base)) {
            Group {
                if let base {
                    RouteDestination(route: base)
                        .stackScreen(base, on: router)
                        // Another place is another screen, with its own models.
                        .id(base)
                } else {
                    fallback
                        .stackScreen(nil, on: router)
                }
            }
            .navigationDestination(for: Route.self) { route in
                RouteDestination(route: route)
                    .stackScreen(route, on: router)
            }
            .hidesTabBarOnGalleries(router)
        }
        .environment(router)
    }

    private func pushed(over base: Route?) -> Binding<[Route]> {
        Binding(
            get: { base == nil ? router.path : Array(router.path.dropFirst()) },
            set: { router.path = (base.map { [$0] } ?? []) + $0 }
        )
    }
}

extension Route {
    /// Whether this route, at the bottom of the `home` stack, is a place (`AppRouter.place`).
    var isPlace: Bool {
        switch self {
        case .galleryList, .favoritesFolder: true
        case .listSearch, .search, .typedSearch, .detail, .detailChild, .settings: false
        }
    }
}

private extension View {
    /// Around every screen of a stack.
    func stackScreen(_ route: Route?, on router: StackRouter) -> some View {
        modifier(StackScreen(route: route, router: router))
    }

    /// The tab bar is hidden from the stack's root, according to the top route, never by the
    /// destination: the bar and its accessory then come back in the same frame after Back
    /// (`spikes/S3.md` section 3). Under `command` there is no tab bar and this does nothing.
    func hidesTabBarOnGalleries(_ router: StackRouter) -> some View {
        toolbarVisibility(router.hidesBrowseChrome ? .hidden : .automatic, for: .tabBar)
    }
}

private struct StackScreen: ViewModifier {
    let route: Route?
    let router: StackRouter

    func body(content: Content) -> some View {
        content
            .chromeScreen(route)
            // Outside the screen's own insets, on the screens that keep the tab bar.
            .modifier(TabsBarLegacyAccessory(isAllowed: route?.hidesBrowseChrome != true))
            // On the screen as well as on the stack: a split view hosts pushed screens outside
            // whatever wraps the stack, and a screen without its router crashes.
            .environment(router)
    }
}
