import EhFeatures
import EhModels
import SwiftUI

/// The `command` bar's shell (`wall.md` section 1): one stack whose root is the first
/// screen, with the command bar at its bottom, across pushes. On a gallery page the bar's
/// three shapes become the page's dock.
///
/// The stack, its bottom chrome and the first screen's column are the shell's
/// (`HomeStackHost`), which hands the bar the top screen's control; this folder draws the bar.
struct CommandShell: View {
    let model: AppModel

    /// The scope the search surface is open on, or `nil` while it is closed.
    @State private var search = CommandBarSearch()

    var body: some View {
        let router = model.router
        // The bar is hidden while the search surface is open: the surface draws its own field
        // bar, and Wall's backdrop is a material the bar would show through.
        HomeStackHost(router: router.home, hasBar: true, isCovered: search.scope != nil) { control, perform in
            CommandBar(router: router, control: control, perform: perform) { scope in
                search.scope = scope
            }
        }
        .searchSurfaceCover(scope: $search.scope, over: router.home)
    }
}

nonisolated struct CommandBarSearch: Equatable, Sendable {
    var scope: SearchScope?
}
