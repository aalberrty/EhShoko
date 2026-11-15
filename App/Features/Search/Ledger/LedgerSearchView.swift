import EhFeatures
import SwiftUI

/// Ledger's search surface (`ledger.md` section 6): "Search" as the screen's own title, the
/// copied-link card, then the groups (Tags while typing, Saved, Recent, and before typing
/// Recently viewed), and the field above the keyboard with the scope on its magnifier, the
/// Filters circle trailing and a row of namespace keys on top of the keyboard.
///
/// `SearchSurface` gives it the model and, in the environment, the field's controller.
/// Everything here only lays out: what is typed goes from the field to the model, and every
/// edit, search and focus goes through the controller. Under `command` it draws its own
/// Cancel in the top bar, so the surface adds no Close.
struct LedgerSearchView: View {
    let model: SearchSurfaceModel

    @Environment(\.look) private var look
    @Environment(\.searchFieldController) private var field
    @Environment(\.searchSurfacePresentation) private var presentation

    var body: some View {
        LedgerSearchList(model: model)
            .background(look.background)
            // For the app switcher and VoiceOver's screen name; the list draws the title in the
            // look's title face, and the bar shows it once that has scrolled away.
            .navigationTitle(L10n.Localizable.SearchView.Title.search)
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                // Under `tabs` the surface is the tab's root: there is nothing to cancel, and
                // the keyboard goes away with a drag of the list or with Search.
                if presentation.canClose {
                    ToolbarItem(placement: .topBarTrailing) {
                        // The app has no generic "Cancel" yet; the jump-to-page alert's is the
                        // same word in every language.
                        Button(L10n.Localizable.JumpPageView.Button.cancel) { field.close() }
                    }
                }
            }
            .searchSurfaceDrawsClose()
            .searchFieldBar {
                SearchFieldCapsule {
                    SearchScopeMenu(model: model)
                } field: {
                    TagSearchField(model: model, prompt: model.scope.localizedPrompt, tokenStyle: .tint) {
                        LedgerSearchKeys()
                    }
                }
                SearchFiltersButton(model: model)
            }
            #if DEBUG || HARNESS
            // Quick and recent searches for the part harness (`-HarnessSearchWords YES`). The
            // seeder is G1's and is to move to `Search/Shared/Harness` (F27); it is shared
            // here rather than copied.
            .task { await ShelfSearchSampleWords.addIfRequested(hasQuickSearches: !model.root.quickSearchWords.isEmpty) }
            #endif
    }
}
