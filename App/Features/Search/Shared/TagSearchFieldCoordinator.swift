import EhFeatures
import EhModels
import UIKit

/// The field's delegate: it keeps the site's syntax as the user types, turns complete terms
/// and chosen suggestions into tokens, and reports every edit to the model
/// (`spikes/S6.md` sections 1 to 3).
@MainActor
final class TagSearchFieldCoordinator: NSObject, UISearchTextFieldDelegate {
    weak var field: TagSearchTextField?
    weak var model: SearchSurfaceModel?
    weak var controller: TagSearchFieldController?
    /// What the field held when it last reported, so an unchanged field reports nothing.
    private var lastReported: TagSearchFieldEdit?
    /// The model's `revision` the field last showed the content of.
    private(set) var appliedRevision: Int?

    init(model: SearchSurfaceModel) {
        self.model = model
    }

    var isFocused: Bool { field?.isFirstResponder ?? false }

    func focus() {
        guard let field else { return }
        field.wantsFocus = true
        field.takeFocusIfWanted()
    }

    func blur() {
        field?.wantsFocus = false
        field?.resignFirstResponder()
    }

    func fieldWillGo() {
        model?.cancel()
        field = nil
    }

    // MARK: Typing

    // Every keystroke of the keyboard comes here before UIKit changes the text; `insertText`
    // from code does not.
    func textField(
        _ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String
    ) -> Bool {
        // Legacy's normalisation, done at the caret instead of rewriting the whole text: a
        // full-width colon goes in as `:`, and a second space in a row is not typed.
        if string.contains("：") {
            textField.insertText(string.replacingOccurrences(of: "：", with: ":"))
            return false
        }
        if string == " ", range.location > 0, let text = textField.text as NSString?,
           range.location <= text.length,
           text.substring(with: NSRange(location: range.location - 1, length: 1)) == " " {
            return false
        }
        return true
    }

    @objc func editingChanged() {
        tokenizeCompletedTerm()
        reportIfChanged()
    }

    func textFieldShouldClear(_ textField: UITextField) -> Bool {
        // The clear button empties the field after this returns, without an editing event.
        Task { @MainActor [weak self] in self?.reportIfChanged() }
        return true
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        controller?.submit()
        return false
    }

    // Copying a token copies the term the site understands.
    func searchTextField(
        _ searchTextField: UISearchTextField, itemProviderForCopying token: UISearchToken
    ) -> NSItemProvider {
        NSItemProvider(object: (token.searchToken?.term ?? "") as NSString)
    }

    // MARK: Edits from the design

    func insertAtCaret(_ key: String) {
        guard let field else { return }
        if !field.isFirstResponder { focus() }
        let space = SearchTokens.needsSpace(beforeKey: key, after: characterBeforeCaret(in: field))
        field.insertText(space ? " " + key : key)
        reportIfChanged()
    }

    func accept(_ suggestion: TagSuggestion) {
        guard let field else { return }
        let caret = field.selectedTextRange?.start ?? field.textualRange.end
        let before = text(from: field.textualRange.start, to: caret, in: field)
        let keyword = suggestion.tag.searchKeyword
        let replacement = SearchTokens.replacement(
            for: suggestion.originalKeyword, keyword: keyword, beforeCaret: before
        )
        let start = replacement.flatMap { field.position(from: caret, offset: -$0.length) } ?? caret
        guard let token = SearchToken(term: replacement?.term ?? keyword),
              let range = field.textRange(from: start, to: caret) else { return }
        replace(range, with: token, in: field)
        reportIfChanged()
    }

    /// The model's content, after it replaced it (`replaceKeyword`): the only time the field
    /// is written from outside.
    func apply(_ model: SearchSurfaceModel) {
        guard let field else { return }
        appliedRevision = model.revision
        field.tokens = model.tokens.map { $0.makeFieldToken() }
        field.text = model.text
        lastReported = currentEdit()
    }

    // MARK: Reporting

    func reportIfChanged() {
        let edit = currentEdit()
        guard edit != lastReported else { return }
        lastReported = edit
        model?.fieldDidEdit(edit)
    }

    private func currentEdit() -> TagSearchFieldEdit {
        guard let field else { return .empty }
        let caret = field.selectedTextRange?.start ?? field.textualRange.end
        return TagSearchFieldEdit(
            tokens: field.tokens.compactMap(\.searchToken),
            text: field.text ?? "",
            beforeCaret: text(from: field.textualRange.start, to: caret, in: field)
        )
    }

    // MARK: Tokens

    /// A space typed after a complete `namespace:tag$` term turns the term into a token.
    private func tokenizeCompletedTerm() {
        guard let field, let caret = field.selectedTextRange?.start, field.compare(caret, to: field.textualRange.start) == .orderedDescending
        else { return }
        let before = text(from: field.textualRange.start, to: caret, in: field)
        guard let term = SearchTokens.completedTerm(beforeCaret: before), let token = SearchToken(term: term),
              let start = field.position(from: caret, offset: -((term as NSString).length + 1)),
              let range = field.textRange(from: start, to: caret) else { return }
        replace(range, with: token, in: field)
    }

    /// Replaces `range` of the text with `token`, after the tokens already there. A token the
    /// field already holds is not added twice: the text is only removed.
    ///
    /// UIKit selects the new token, so the next keystroke would replace it; the caret goes
    /// back where the replaced text started.
    private func replace(_ range: UITextRange, with token: SearchToken, in field: UISearchTextField) {
        let offset = field.offset(from: field.textualRange.start, to: range.start)
        if field.tokens.contains(where: { $0.searchToken == token }) {
            field.replace(range, withText: "")
        } else {
            field.replaceTextualPortion(of: range, with: token.makeFieldToken(), at: field.tokens.count)
        }
        if let caret = field.position(from: field.textualRange.start, offset: max(0, offset)) {
            field.selectedTextRange = field.textRange(from: caret, to: caret)
        }
    }

    // MARK: Text positions

    private func text(from start: UITextPosition, to end: UITextPosition, in field: UITextField) -> String {
        guard field.compare(start, to: end) != .orderedDescending, let range = field.textRange(from: start, to: end)
        else { return "" }
        return field.text(in: range) ?? ""
    }

    private func characterBeforeCaret(in field: UISearchTextField) -> Character? {
        guard let caret = field.selectedTextRange?.start,
              field.compare(caret, to: field.textualRange.start) == .orderedDescending,
              let start = field.position(from: caret, offset: -1)
        else { return nil }
        return text(from: start, to: caret, in: field).last
    }
}
