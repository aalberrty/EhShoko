import EhFeatures
import EhNetworking
import SwiftUI

/// The handle a search design uses to act on the field and the surface (`spikes/S6.md`
/// section 11): focus, edits at the caret, new content, submitting and closing.
///
/// `SearchSurface` owns one for as long as the surface is shown, puts it in the environment
/// (`\.searchFieldController`) and attaches the model, the stack and the presentation to it.
/// The field registers itself when it is made. It is not observable: nothing redraws when it
/// changes, and calling it from a button costs a view nothing.
///
/// **The field leads; the model follows.** What the user types goes from the field to the
/// model, never back. New content reaches the field only through this controller (`use`,
/// `clear`, `accept`, `insert`): the model's own editing methods (`use`, `clear`, `accept`,
/// `removeToken`) change the model and not the field, so a design does not call them.
@MainActor
final class TagSearchFieldController {
    private weak var coordinator: TagSearchFieldCoordinator?
    private weak var model: SearchSurfaceModel?
    private weak var stack: StackRouter?
    private var presentation = SearchSurfacePresentation.tab
    private var openURL: OpenURLAction?
    /// Focus asked for before a field registered.
    private var wantsFocus = false

    nonisolated init() {}

    // MARK: What the surface attaches

    /// Called by `SearchSurface` when it appears.
    func attach(
        model: SearchSurfaceModel, stack: StackRouter, presentation: SearchSurfacePresentation, openURL: OpenURLAction
    ) {
        self.model = model
        self.stack = stack
        self.presentation = presentation
        self.openURL = openURL
    }

    /// Called by the field when it is made, and again when it is updated.
    func register(_ coordinator: TagSearchFieldCoordinator) {
        guard self.coordinator !== coordinator else { return }
        self.coordinator = coordinator
        if wantsFocus {
            wantsFocus = false
            coordinator.focus()
        }
    }

    // MARK: Focus

    /// Whether the surface is an overlay that can be closed (under `command`), rather than the
    /// Search tab's root.
    var canClose: Bool { presentation.canClose }

    var isFocused: Bool { coordinator?.isFocused ?? false }

    /// Focuses the field now, or as soon as it is in a window.
    func focus() {
        if let coordinator {
            coordinator.focus()
        } else {
            wantsFocus = true
        }
    }

    func blur() {
        wantsFocus = false
        coordinator?.blur()
    }

    // MARK: Editing at the caret

    /// Inserts `text` at the caret, replacing a selection, as a key of the keyboard does
    /// (Ledger's keys). A namespace key typed right after a word gets a space before it.
    func insert(_ text: String) {
        coordinator?.insertAtCaret(text)
    }

    /// The fragment the suggestion matched, just before the caret, becomes its token. A `-` or
    /// `~` typed before the fragment becomes the token's mark.
    func accept(_ suggestion: SearchTagSuggestion) {
        coordinator?.accept(suggestion.suggestion)
    }

    // MARK: New content

    /// Puts `keyword` in the field (a recent search, a quick search, the keyword of the
    /// results the surface was opened from): its tags as tokens, the rest as text.
    func use(_ keyword: String) {
        guard let model else { return }
        model.use(keyword)
        // Suggestions are for typing; a keyword handed in shows none until the next keystroke.
        model.suggestions.textDidChange("")
        coordinator?.apply(tokens: model.tokens, text: model.text)
    }

    func clear() {
        model?.clear()
        coordinator?.apply(tokens: [], text: "")
    }

    // MARK: Submitting and closing

    /// Searches the field's keyword in the model's scope: the results are pushed on the stack
    /// the surface is on, and the list part draws them. Under `command` that closes the
    /// surface. Return in the field does this.
    func submit() {
        coordinator?.reportIfChanged()
        blur()
        guard let model, let stack else { return }
        model.submit(on: stack)
    }

    /// Puts `keyword` in the field and searches it: a recent or quick search tapped.
    func search(_ keyword: String) {
        use(keyword)
        submit()
    }

    /// Closes the surface under `command`; under `tabs`, where there is nothing to close, it
    /// puts the keyboard away.
    func close() {
        blur()
        presentation.close()
    }

    /// The copied-link offer's "Open": reads the link (the system may ask to paste) and opens
    /// it as a shared link opens, in the gallery sheet. Does nothing when it is not a link to
    /// a gallery.
    func openCopiedLink() {
        guard let url = model?.openLink(), let link = SearchCopiedLink.appLink(for: url) else { return }
        blur()
        openURL?(link)
    }
}

/// Turns a link read from the clipboard into the app's own link, which the shell opens the
/// way it opens a shared one (as Ledger's Index does with a pasted link).
nonisolated enum SearchCopiedLink {
    /// The scheme the share extension rewrites links to; `EhURL.resolvingAppScheme` turns it
    /// back.
    private static let appScheme = "ehshoko"

    static func appLink(for url: URL) -> URL? {
        guard EhURL.isHandleable(url), var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return nil }
        components.scheme = appScheme
        return components.url
    }
}

extension EnvironmentValues {
    /// The search field's controller, set by `SearchSurface` for its design. Outside a surface
    /// it is a controller with no field, on which every call does nothing.
    @Entry var searchFieldController = TagSearchFieldController()
}
