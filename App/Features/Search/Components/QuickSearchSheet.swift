import EhFeatures
import EhModels
import SwiftUI

/// Saved search keywords, presented as a sheet (legacy `QuickSearchView`), on the look's
/// tokens: its surface as the ground, its raised colour for the rows, the words in its face for
/// search syntax. The sheet is the system's: no `presentationBackground`, no glass in the rows.
///
/// Tapping a word calls `onSelect` with its content; the caller closes the sheet.
struct QuickSearchSheet: View {
    let onSelect: (String) -> Void

    @State private var model = QuickSearchModel()

    var body: some View {
        NavigationStack {
            QuickSearchList(model: model, onSelect: onSelect)
                .navigationTitle(L10n.Localizable.QuickSearchView.Title.quickSearch)
                .toolbar { toolbar }
                .navigationDestination(item: $model.editor) { editor in
                    QuickSearchWordForm(model: model, editor: editor)
                }
        }
        .task { await model.observe() }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button(L10n.Localizable.QuickSearchView.Title.newWord, systemImage: "plus", action: model.startAdding)
            // The symbol carries the system's localized "Edit" label for VoiceOver.
            Button(action: model.toggleEditing) {
                Image(systemName: "pencil.circle")
                    .symbolVariant(model.isEditing ? .fill : .none)
            }
        }
    }
}

private struct QuickSearchList: View {
    @Bindable var model: QuickSearchModel
    let onSelect: (String) -> Void

    @Environment(\.look) private var look

    var body: some View {
        List {
            ForEach(model.words) { word in
                Button { onSelect(word.content) } label: {
                    QuickSearchWordRow(word: word, showsDisclosure: !model.isEditing)
                }
                .tint(look.label)
                .lookFormRow()
                .swipeActions(edge: .trailing) {
                    Button(L10n.Localizable.ConfirmationDialog.Button.delete, systemImage: "trash") {
                        model.requestDeletion(of: word)
                    }
                    .tint(.red)
                    Button(L10n.Localizable.QuickSearchView.Title.editWord, systemImage: "square.and.pencil") {
                        model.startEditing(word)
                    }
                }
            }
            .onDelete { offsets in
                Task { await model.delete(atOffsets: offsets) }
            }
            .onMove { source, destination in
                Task { await model.move(fromOffsets: source, toOffset: destination) }
            }
        }
        .lookFormStyle()
        .overlay {
            if model.words.isEmpty {
                if model.isLoading {
                    LoadingStateView()
                } else {
                    EmptyStateView()
                }
            }
        }
        .environment(\.editMode, editMode)
        .animation(.default, value: model.words)
        .animation(.default, value: model.isEditing)
        .confirmationDialog(
            L10n.Localizable.ConfirmationDialog.Title.delete,
            isPresented: isConfirmingDeletion,
            titleVisibility: .visible,
            presenting: model.pendingDeletion
        ) { _ in
            Button(L10n.Localizable.ConfirmationDialog.Button.delete, role: .destructive) {
                Task { await model.confirmDeletion() }
            }
        }
    }

    private var editMode: Binding<EditMode> {
        Binding(
            get: { model.isEditing ? .active : .inactive },
            set: { model.isEditing = $0.isEditing }
        )
    }

    private var isConfirmingDeletion: Binding<Bool> {
        Binding(
            get: { model.pendingDeletion != nil },
            set: { if !$0 { model.pendingDeletion = nil } }
        )
    }
}

private struct QuickSearchWordRow: View {
    let word: QuickSearchWord
    let showsDisclosure: Bool

    @Environment(\.look) private var look

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: Tokens.Spacing.xSmall) {
                if !word.name.isEmpty {
                    Text(word.name)
                        .font(.subheadline)
                        .foregroundStyle(look.secondaryLabel)
                        .lineLimit(1)
                }
                Text(word.content)
                    .font(.title3.weight(.medium))
                    .lookSyntaxDesign()
                    .foregroundStyle(look.label)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            if showsDisclosure {
                Image(systemName: "chevron.forward")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(look.tertiaryLabel)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, Tokens.Spacing.xSmall)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

/// The form that adds or edits a word, pushed inside the sheet.
private struct QuickSearchWordForm: View {
    private enum Field { case name, content }

    @Bindable var model: QuickSearchModel
    let editor: QuickSearchEditor

    @FocusState private var focusedField: Field?

    var body: some View {
        Form {
            Section {
                TextField(L10n.Localizable.QuickSearchView.Placeholder.optional, text: $model.draft.name)
                    .submitLabel(.next)
                    .focused($focusedField, equals: .name)
                    .onSubmit { focusedField = .content }
                    .lookFormRow()
            } header: {
                Text(L10n.Localizable.QuickSearchView.Title.name)
                    .lookFormHeader()
            }
            Section {
                TextEditor(text: $model.draft.content)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .lookSyntaxDesign()
                    // The row's raised colour shows through, as behind the name field.
                    .scrollContentBackground(.hidden)
                    .focused($focusedField, equals: .content)
                    .frame(minHeight: 88)
                    .lookFormRow()
            } header: {
                Text(L10n.Localizable.QuickSearchView.Title.content)
                    .lookFormHeader()
            }
        }
        .lookFormStyle()
        .navigationTitle(title)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                SheetConfirmButton {
                    Task { await model.saveDraft() }
                }
                .disabled(!model.canSaveDraft)
            }
        }
    }

    private var title: String {
        switch editor {
        case .newWord: L10n.Localizable.QuickSearchView.Title.newWord
        case .editWord: L10n.Localizable.QuickSearchView.Title.editWord
        }
    }
}

#Preview {
    Color.clear.sheet(isPresented: .constant(true)) {
        QuickSearchSheet { _ in }
    }
}
