import EhFeatures
import SwiftUI

/// Wall's search surface (`wall.md` section 6): everything anchored to the bottom, over one
/// standard material that covers the screen the search was opened from.
///
/// From the keyboard up: the field, with the scope menu on its magnifier, and a Close circle;
/// then the suggestions in reverse order, the best match nearest the thumb and highlighted, or
/// before anything is typed the recent searches, the newest nearest the field; a Filters row
/// at the top of them; the quick searches; and before typing, the recently seen covers.
///
/// `SearchSurface` gives it the model and, in the environment, the field's controller and the
/// presentation. Everything here only lays out: what is typed goes from the field to the
/// model, and every edit, search and focus goes through the controller.
struct WallSearchView: View {
    let model: SearchSurfaceModel

    /// Whether something is typed after the tokens, which swaps the recent searches for the
    /// suggestions. It changes when typing starts or stops, not per keystroke.
    @State private var isTyping = false
    @Environment(\.searchSurfacePresentation) private var presentation
    @Environment(\.searchFieldController) private var field
    @Environment(\.look) private var look
    @Environment(\.accessibilityReduceTransparency) private var reducesTransparency

    var body: some View {
        WallSearchStack(model: model, isTyping: isTyping)
            .background { WallSearchTypingProbe(model: model, isTyping: $isTyping) }
            // An inline title keeps the system bar, whose scroll edge effect takes the rows
            // that scroll up past the top; without it they run under the status bar.
            .navigationTitle(L10n.Localizable.SearchView.Title.search)
            .navigationBarTitleDisplayMode(.inline)
            .containerBackground(backdrop, for: .navigation)
            .searchFieldBar {
                SearchFieldCapsule {
                    SearchScopeMenu(model: model)
                } field: {
                    // White token text does not read on Wall's drawn fill: a solid grey
                    // (`spikes/S6.md` section 10).
                    TagSearchField(model: model, prompt: model.scope.localizedPrompt, tokenStyle: .grey)
                }
                // Under `tabs` the surface is the tab's root and there is nothing to close.
                if presentation.canClose {
                    SearchFieldCircleButton(systemImage: "xmark", title: L10n.Localizable.Common.close) {
                        field.close()
                    }
                }
            }
            .searchSurfaceDrawsClose()
            #if DEBUG || HARNESS
            .searchDesignHarness(model: model)
            #endif
    }

    /// Over the screen it was opened from, one standard material, which is a background and not
    /// glass (`README.md` section 13); the look's surface when transparency is reduced. The
    /// Search tab's root covers nothing, so it stands on the look's ground.
    private var backdrop: AnyShapeStyle {
        guard presentation.canClose else { return AnyShapeStyle(look.background) }
        return reducesTransparency ? AnyShapeStyle(look.surface) : AnyShapeStyle(.ultraThinMaterial)
    }
}

/// Turns the typed text into "something is typed", for the screen to hold.
///
/// The only view of Wall's search that reads `model.text`, so a keystroke re-evaluates this
/// small body and nothing else; the screen around it changes only when typing starts or stops.
private struct WallSearchTypingProbe: View {
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
