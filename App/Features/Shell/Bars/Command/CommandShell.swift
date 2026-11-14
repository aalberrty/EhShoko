import EhFeatures
import EhModels
import SwiftUI

/// The `command` bar (`Design/designs/README.md` section 5.1, `wall.md` section 1): one
/// stack whose root is the first screen, with the command bar at its bottom, across pushes.
/// On a gallery page the bar's three shapes become the page's dock.
///
/// A first working form: task A2 builds the bar itself in this folder. What is the shell's
/// stays: the one `HomeStackHost`, and the bar being given the top screen's control.
struct CommandShell: View {
    let model: AppModel

    /// The scope the search surface is open on, or `nil` while it is closed.
    @State private var search = CommandBarSearch()

    var body: some View {
        let router = model.router
        HomeStackHost(router: router.home, hasBar: true) { control, perform in
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
