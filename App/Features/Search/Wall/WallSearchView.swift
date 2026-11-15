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
    @Environment(\.look) private var look
    @Environment(\.accessibilityReduceTransparency) private var reducesTransparency

    var body: some View {
        WallSearchStack(model: model, isTyping: isTyping)
            .background { WallSearchTypingProbe(model: model, isTyping: $isTyping) }
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
                    WallSearchCloseButton()
                }
            }
            .searchSurfaceDrawsClose()
            #if DEBUG || HARNESS
            // `-HarnessSearchWords YES`: G1's sample quick and recent searches, until they move
            // to `Search/Shared/Harness`.
            .task { await ShelfSearchSampleWords.addIfRequested(hasQuickSearches: !model.root.quickSearchWords.isEmpty) }
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

/// The Close circle beside the field under `command`: puts the keyboard away and closes the
/// surface. The same glass circle as the shared ones (`SearchFieldCircleButton`: 52 pt,
/// growing to 64 pt), but labelled by its symbol, whose "Close" the system translates; the
/// app has no string of its own for it.
private struct WallSearchCloseButton: View {
    @ScaledMetric(relativeTo: .body) private var height: CGFloat = 52
    @Environment(\.searchFieldController) private var field
    @Environment(\.look) private var look

    var body: some View {
        let size = min(height, 64)
        Button {
            field.close()
        } label: {
            Image(systemName: "xmark")
                .font(.body.weight(.semibold))
                .foregroundStyle(look.label)
                .frame(width: size, height: size)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .glassSurface(in: .circle, isInteractive: true)
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .accessibilityShowsLargeContentViewer()
    }
}
