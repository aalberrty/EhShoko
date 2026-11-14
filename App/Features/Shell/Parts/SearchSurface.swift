import EhCore
import EhFeatures
import EhModels
import SwiftUI

/// The search surface (`Design/designs/README.md` sections 4 and 5.6): the Search tab's root
/// under `tabs`, and what the command bar's field opens under `command`. The search part's
/// switch point: the one place that reads `designSearch`.
///
/// It owns the shared model, so a change of design keeps what was typed. Submitting pushes
/// the results on the stack in the environment (`SearchSurfaceModel.submit(on:)`); the list
/// part draws them.
///
/// Handed to the search task (F12) with its presentation below.
struct SearchSurface: View {
    private let scope: SearchScope

    @State private var model: SearchSurfaceModel
    @Environment(SettingsStore.self) private var settings

    /// `scope` is where the user came from: Favourites from the library, Watched from
    /// Watched, Everywhere otherwise.
    init(scope: SearchScope) {
        self.scope = scope
        _model = State(initialValue: SearchSurfaceModel(scope: scope))
    }

    var body: some View {
        surface
            // The Search tab keeps its screen while the user visits other tabs; coming back
            // from another one starts on that one's scope.
            .onChange(of: scope) { _, scope in model.scope = scope }
    }

    @ViewBuilder
    private var surface: some View {
        switch settings.designSearch {
        case .shelf: ShelfSearchView(model: model)
        case .wall: WallSearchView(model: model)
        case .ledger: LedgerSearchView(model: model)
        }
    }
}

extension View {
    /// Under `command`: presents the search surface over the stack of `router` while `scope`
    /// is set, and closes it when results are pushed.
    ///
    /// A first working form: a sheet. The search task replaces it with the field rising out
    /// of the bar's centre capsule (`spikes/S2.md` section 4).
    func searchSurfaceCover(scope: Binding<SearchScope?>, over router: StackRouter) -> some View {
        modifier(SearchSurfaceCover(scope: scope, router: router))
    }
}

private struct SearchSurfaceCover: ViewModifier {
    @Binding var scope: SearchScope?
    let router: StackRouter

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: isPresented) {
                NavigationStack {
                    SearchSurface(scope: scope ?? .everywhere)
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                SheetCloseButton { scope = nil }
                            }
                        }
                }
                // Results go onto the stack the surface was opened over.
                .environment(router)
                .pushesGalleries(on: router)
            }
            .onChange(of: router.path) { scope = nil }
    }

    private var isPresented: Binding<Bool> {
        Binding(get: { scope != nil }, set: { if !$0 { scope = nil } })
    }
}
