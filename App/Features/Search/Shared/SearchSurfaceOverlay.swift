import EhFeatures
import SwiftUI

/// How the search surface is shown, which is all a search design learns about where it is.
nonisolated enum SearchSurfacePresentation: Sendable {
    /// The Search tab's root under `tabs`: nothing to close, and the field is not focused when
    /// the tab is chosen (`spikes/S3.md`).
    case tab
    /// Over the screen under `command`, opened from the bar's field: focused at once, closed
    /// by the design's Close or Cancel, by a search, or by the accessibility escape.
    case overlay(close: @MainActor @Sendable () -> Void)

    var canClose: Bool {
        if case .overlay = self { true } else { false }
    }

    @MainActor
    func close() {
        if case .overlay(let close) = self { close() }
    }
}

extension EnvironmentValues {
    /// Set by the presentation around `SearchSurface`; read by the surface, which hands it to
    /// its design through the field's controller.
    @Entry var searchSurfacePresentation = SearchSurfacePresentation.tab
}

/// The search surface over the `command` stack (`spikes/S6.md` section 6): an overlay on the
/// stack's host, placed outside the host's `ignoresSafeArea(.keyboard)`, so the field bar
/// rides on the keyboard as it does under `tabs`.
///
/// The surface is the root of a navigation stack of its own, as it is the root of the Search
/// tab's stack under `tabs`, so a design has the same top bar under both bars. Nothing is
/// pushed on that stack: a search, and a gallery opened from the surface, go onto the stack
/// the surface covers, which closes it.
struct SearchSurfaceOverlay: View {
    let scope: SearchScope
    let router: StackRouter
    let close: @MainActor @Sendable () -> Void

    @Environment(\.look) private var look

    var body: some View {
        NavigationStack {
            SearchSurface(scope: scope, keyword: Self.keyword(of: router.path.last))
        }
        .environment(router)
        .pushesGalleries(on: router)
        .environment(\.searchSurfacePresentation, .overlay(close: close))
        // VoiceOver stays on the surface, and the escape gesture closes it.
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape) { close() }
    }

    /// The keyword of the results the bar's field was showing, which the field starts with.
    static func keyword(of route: Route?) -> String? {
        switch route {
        case .typedSearch(let keyword), .search(let keyword), .listSearch(_, let keyword):
            keyword.isEmpty ? nil : keyword
        default:
            nil
        }
    }
}

/// Presents `SearchSurfaceOverlay` while `scope` is set, and closes it when the stack's path
/// changes: a search pushed its results, or a gallery was opened.
struct SearchSurfaceCover: ViewModifier {
    @Binding var scope: SearchScope?
    let router: StackRouter

    func body(content: Content) -> some View {
        content
            .overlay {
                if let scope {
                    SearchSurfaceOverlay(scope: scope, router: router) { self.scope = nil }
                        .transition(.opacity)
                }
            }
            .animation(.smooth(duration: 0.3), value: scope)
            .onChange(of: router.path) { scope = nil }
    }
}
