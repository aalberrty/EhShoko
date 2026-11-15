import EhFeatures
import SwiftUI

/// Shelf's search surface (`shelf.md` section 6): the scopes as a segmented control in the
/// top bar, quick searches, recent searches and recently seen galleries before anything is
/// typed, suggestions while typing, and the field above the keyboard between the Filters
/// circle and a clear circle.
///
/// `SearchSurface` gives it the model and, in the environment, the field's controller, and
/// adds the Close button under `command`. Everything here only lays out: what is typed goes
/// from the field to the model, and every edit, search and focus goes through the controller.
struct ShelfSearchView: View {
    let model: SearchSurfaceModel

    /// Whether something is typed after the tokens, which picks the list's sections and
    /// lets the clear circle act. It changes when typing starts or stops, not per keystroke.
    @State private var isTyping = false
    @State private var notice: HUDConfiguration?
    @Environment(\.look) private var look

    var body: some View {
        ShelfSearchList(model: model, isTyping: isTyping)
            .background { ShelfSearchTypingProbe(model: model, isTyping: $isTyping) }
            .background(look.background)
            .navigationTitle(L10n.Localizable.SearchView.Title.search)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    ShelfSearchScopes(model: model) {
                        notice = .symbol("person.crop.circle", title: L10n.Localizable.Search.Scope.signin)
                    }
                }
            }
            .searchFieldBar {
                SearchFiltersButton(model: model)
                SearchFieldCapsule {
                    SearchFieldMagnifier()
                } field: {
                    // The clear circle beside the capsule clears; the field's own button would
                    // double it while typing.
                    TagSearchField(
                        model: model, prompt: model.scope.localizedPrompt, tokenStyle: .tint, showsClearButton: false
                    )
                }
                ShelfSearchClearButton(model: model, isTyping: isTyping)
            }
            .hud($notice)
            #if DEBUG || HARNESS
            .searchDesignHarness(model: model)
            #endif
    }
}

/// Turns the typed text into "something is typed", for the screen to hold.
///
/// Besides `SearchTitlesButton`, the only view that reads `model.text`, so a keystroke
/// re-evaluates these two small bodies and nothing else; the screen around them changes only
/// when typing starts or stops.
private struct ShelfSearchTypingProbe: View {
    let model: SearchSurfaceModel
    @Binding var isTyping: Bool

    var body: some View {
        let typing = !model.text.trimmingCharacters(in: .whitespaces).isEmpty
        Color.clear
            .onChange(of: typing, initial: true) { _, typing in
                if isTyping != typing { isTyping = typing }
            }
    }
}

/// The trailing circle: empties the field, tokens and text. Dimmed while there is nothing to
/// clear.
private struct ShelfSearchClearButton: View {
    let model: SearchSurfaceModel
    let isTyping: Bool

    @Environment(\.searchFieldController) private var field

    var body: some View {
        SearchFieldCircleButton(systemImage: "xmark", title: L10n.Localizable.ConfirmationDialog.Button.clear) {
            field.clear()
        }
        .disabled(!isTyping && model.tokens.isEmpty)
    }
}
