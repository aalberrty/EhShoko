import EhCore
import EhFeatures
import EhModels
import SwiftUI

/// The search surface (`Design/designs/README.md` sections 4 and 5.6): the Search tab's root
/// under `tabs`, and what the command bar's field opens under `command`. The search part's
/// switch point: the one place that reads `designSearch`.
///
/// What it gives every search design, so a design only lays out:
/// - the shared model (`SearchSurfaceModel`), kept across a change of design, with its lists
///   kept current and the clipboard checked for a link while the surface is shown;
/// - the field's controller in the environment (`\.searchFieldController`), attached to the
///   model, the stack and the presentation: a design focuses, edits, submits and closes
///   through it, and searching pushes the results on the stack the surface is on, where the
///   list part draws them;
/// - Filters and the quick-search editor, presented here for every design;
/// - under `command`, a Close button in the top bar unless the design draws its own
///   (`searchSurfaceDrawsClose()`), and the field focused as the surface appears.
struct SearchSurface: View {
    private let scope: SearchScope
    private let keyword: String?

    @State private var model: SearchSurfaceModel
    @State private var field = TagSearchFieldController()
    @State private var designDrawsClose = false
    @Environment(SettingsStore.self) private var settings
    @Environment(StackRouter.self) private var stack
    @Environment(\.searchSurfacePresentation) private var presentation
    @Environment(\.openURL) private var openURL

    /// `scope` is where the user came from: Favourites from the library, Watched from
    /// Watched, Everywhere otherwise.
    init(scope: SearchScope) {
        self.init(scope: scope, keyword: nil)
    }

    /// `keyword` is put in the field as the surface appears: the keyword of the results the
    /// command bar's field was showing.
    init(scope: SearchScope, keyword: String?) {
        self.scope = scope
        self.keyword = keyword
        #if DEBUG || HARNESS
        _model = State(initialValue: SearchSampleSuggestions.model(scope: scope))
        #else
        _model = State(initialValue: SearchSurfaceModel(scope: scope))
        #endif
    }

    var body: some View {
        surface
            .environment(\.searchFieldController, field)
            .onPreferenceChange(SearchSurfaceDrawsCloseKey.self) { designDrawsClose = $0 }
            .toolbar {
                if presentation.canClose, !designDrawsClose {
                    ToolbarItem(placement: .cancellationAction) {
                        SheetCloseButton { field.close() }
                    }
                }
            }
            .modifier(SearchSurfaceSheets(root: model.root, scope: model.scope, controller: field))
            // The Search tab keeps its screen while the user visits other tabs; coming back
            // from another one starts on that one's scope.
            .onChange(of: scope) { _, scope in model.scope = scope }
            .onAppear(perform: appear)
            .onDisappear { model.cancel() }
            .task { await model.observe() }
            .task { await model.checkForLink() }
            #if DEBUG || HARNESS
            .onAppear {
                SearchKeystrokeProbe.runIfRequested(field: field, model: model) { [model] in
                    "keyword \(model.keyword) | tokens \(model.tokens.map(\.term)) | text \(model.text)"
                }
            }
            #endif
    }

    @ViewBuilder
    private var surface: some View {
        #if DEBUG || HARNESS
        if SearchSampleSurface.isRequested {
            SearchSampleSurface(model: model)
        } else {
            design
        }
        #else
        design
        #endif
    }

    @ViewBuilder
    private var design: some View {
        switch settings.designSearch {
        case .shelf: ShelfSearchView(model: model)
        case .wall: WallSearchView(model: model)
        case .ledger: LedgerSearchView(model: model)
        }
    }

    private func appear() {
        field.attach(model: model, stack: stack, presentation: presentation, openURL: openURL)
        if let keyword, model.isEmpty {
            field.use(keyword)
        }
        // Opened by tapping the bar's field: the keyboard comes up with it. The Search tab is
        // only chosen, so it waits for a tap in the field (`spikes/S3.md`).
        if presentation.canClose {
            field.focus()
        }
    }
}

extension View {
    /// Under `command`: presents the search surface over the stack of `router` while `scope`
    /// is set, and closes it when results are pushed or a gallery is opened.
    ///
    /// The surface is an overlay of the view this modifies, which must be outside the bottom
    /// chrome's keyboard-ignoring area (`spikes/S6.md` section 6): the field bar then rises
    /// to the keyboard, at the height it has under `tabs`.
    func searchSurfaceCover(scope: Binding<SearchScope?>, over router: StackRouter) -> some View {
        modifier(SearchSurfaceCover(scope: scope, router: router))
    }

    /// A search design that draws its own Close or Cancel (Wall's circle, Ledger's Cancel)
    /// says so, and the surface adds none to the top bar under `command`.
    func searchSurfaceDrawsClose() -> some View {
        preference(key: SearchSurfaceDrawsCloseKey.self, value: true)
    }
}

private struct SearchSurfaceDrawsCloseKey: PreferenceKey {
    static let defaultValue = false

    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}
