import EhFeatures
import EhModels
import SwiftUI

/// What Wall's list puts around its covers (`wall.md` section 3, `Design/designs/README.md`
/// section 5.3): the place's name as a small title in the top bar, unless a first screen draws
/// it; the More menu with every list control and the three densities, always, as the top bar's
/// trailing item; and the find field when "Find in this list" is on.
///
/// The bar and its items are the system's (`README.md` section 13). Toplists' period and page
/// menus and the filter pill are not here: they scroll with the covers (`WallListTop`). The
/// list draws no bottom bar.
struct WallListChrome: ViewModifier {
    let input: ListDesignInput
    let density: WallDensity
    let setDensity: (WallDensity) -> Void

    func body(content: Content) -> some View {
        content
            .listFindBar(isPresented: isFinding, text: findText)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    ListMoreMenu(controls: input.controls.menu, perform: input.perform) {
                        WallDensityMenu(density: density, choose: setDensity)
                    }
                }
            }
            .modifier(WallListTitle(context: input.context))
    }

    private var isFinding: Binding<Bool> {
        Binding(
            get: { input.controls.isFinding },
            set: { isFinding in
                // The list toggles it, and clears the text when it closes.
                if isFinding != input.controls.isFinding { input.perform(.find) }
            }
        )
    }

    private var findText: Binding<String> {
        Binding(get: { input.feed.findText }, set: { input.feed.findText = $0 })
    }
}

/// The list's own title, unless it is embedded in a first screen or the library, which draw
/// theirs. Small, in the bar's own row, so the covers start right under the bar. A large title
/// was tried: when the command bar's place menu swaps the list in place, the bar shows it
/// collapsed until the list is scrolled, so the same list had two looks.
private struct WallListTitle: ViewModifier {
    let context: ListContext

    func body(content: Content) -> some View {
        if context.embedsInStart {
            content
        } else {
            content
                .navigationTitle(context.title)
                .toolbarTitleDisplayMode(.inline)
        }
    }
}
