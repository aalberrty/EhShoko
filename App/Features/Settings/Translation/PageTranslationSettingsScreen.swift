import EhCore
import EhFeatures
import EhModels
import SwiftUI

/// Settings › Translation (`README.md` section 9.1): where the models of the current choices
/// stand and their one button, the four choices, storage, the private model source, and the
/// credits. There is no switch for translation here: it is pressed in the reader.
///
/// Opening it reads nothing from disk on the main actor: the model asks the store to look at
/// its folder, which it does elsewhere, and the figures are a static table.
struct PageTranslationSettingsScreen: View {
    @State private var model = PageTranslationSettingsModel.forScreen()
    @Environment(\.look) private var look

    private typealias Strings = L10n.Localizable.Settings.Translation

    var body: some View {
        List {
            PageTranslationTopCard(model: model)
            modelsSection
            PageTranslationStorageSection(model: model)
            PageTranslationSourceSection(model: model)
            licencesSection
        }
        .settingsFormStyle()
        .navigationTitle(L10n.Localizable.Settings.translation)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            #if DEBUG
            await PageTranslationSample.prepare()
            #endif
            await model.load()
        }
    }

    private var modelsSection: some View {
        Section {
            ForEach(ModelRole.allCases, id: \.self) { role in
                NavigationLink(value: child(.choices(role))) {
                    LabeledContent {
                        Text(verbatim: model.current(role).displayName)
                    } label: {
                        Text(role.title).foregroundStyle(look.label)
                    }
                }
            }
        } header: {
            Text(Strings.models).settingsSectionHeader()
        }
        .settingsRow()
    }

    private var licencesSection: some View {
        Section {
            NavigationLink(value: child(.licences)) {
                Text(Strings.licences).foregroundStyle(look.label)
            }
        } footer: {
            Text(Strings.footer(PageTranslationDevice.name)).settingsFootnote()
        }
        .settingsRow()
    }

    private func child(_ destination: PageTranslationChildRoute.Destination) -> Route {
        .settings(.pageTranslationChild(PageTranslationChildRoute(parent: model, destination: destination)))
    }
}

extension PageTranslationSettingsModel {
    /// The screen's model; in debug builds launched with `-PageTranslationSample`, one over the
    /// sample store.
    static func forScreen() -> PageTranslationSettingsModel {
        #if DEBUG
        if let model = PageTranslationSample.makeModel() { return model }
        #endif
        return PageTranslationSettingsModel()
    }
}

/// The first card: "Japanese → 简体中文, on this iPhone", where the current models stand, the one
/// button (Download with the size, Pause, Resume or Try again), and under it what the current
/// detector and reader read together on the test pages.
private struct PageTranslationTopCard: View {
    let model: PageTranslationSettingsModel

    @Environment(\.look) private var look

    var body: some View {
        let state = model.setState
        let headline = L10n.Localizable.Settings.Translation.headline(
            L10n.Localizable.Reader.Translate.target, PageTranslationDevice.name
        )
        Section {
            VStack(alignment: .leading, spacing: Tokens.Spacing.small) {
                Label {
                    Text(headline).font(.headline)
                } icon: {
                    Image(systemName: "translate")
                }
                .foregroundStyle(look.label)
                // The symbol is decoration: without this a list reads it as "Translate".
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(headline))
                .accessibilityAddTraits(.isHeader)
                Text(state.settingsStatusText)
                    .font(.subheadline)
                    .foregroundStyle(look.secondaryLabel)
                if let progress = state.progress {
                    ProgressView(value: progress.fraction)
                }
                if let detail = state.settingsDetail(isConnected: model.isConnected) {
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(look.secondaryLabel)
                }
                if let action = model.topAction {
                    Button(action.title) { model.performTopAction() }
                        .buttonStyle(.borderedProminent)
                        .padding(.top, Tokens.Spacing.xSmall)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, Tokens.Spacing.xSmall)
        } footer: {
            Text(model.pair.pairText).settingsFootnote()
        }
        .settingsRow()
    }
}

/// Models on this device with the total and a Delete for each (swipe) and for all; the
/// translated pages with their size and Clear.
private struct PageTranslationStorageSection: View {
    let model: PageTranslationSettingsModel

    @State private var isConfirmingDeleteAll = false
    @State private var isConfirmingClear = false
    @Environment(\.look) private var look

    private typealias Storage = L10n.Localizable.Settings.Translation.Storage

    var body: some View {
        Section {
            LabeledContent {
                Text(model.installedBytes.byteText)
            } label: {
                Text(Storage.models(PageTranslationDevice.name)).foregroundStyle(look.label)
            }
            ForEach(model.installedModels) { installed in
                installedRow(installed)
            }
            Button(Storage.deleteAll, role: .destructive) { isConfirmingDeleteAll = true }
                .disabled(!model.canDeleteAll)
                .confirmationDialog(
                    Storage.DeleteAll.message, isPresented: $isConfirmingDeleteAll, titleVisibility: .visible
                ) {
                    Button(L10n.Localizable.ConfirmationDialog.Button.delete, role: .destructive) {
                        Task { await model.deleteAll() }
                    }
                }
            translatedPages
        } header: {
            Text(L10n.Localizable.Settings.Translation.storage).settingsSectionHeader()
        }
        .settingsRow()
    }

    private func installedRow(_ installed: InstalledPageTranslationModel) -> some View {
        LabeledContent {
            Text(installed.bytes.byteText)
        } label: {
            VStack(alignment: .leading, spacing: Tokens.Spacing.xxSmall) {
                Text(verbatim: installed.choice?.displayName ?? installed.name)
                    .foregroundStyle(look.label)
                if let role = installed.choice?.role {
                    Text(role.title)
                        .font(.footnote)
                        .foregroundStyle(look.secondaryLabel)
                }
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(L10n.Localizable.ConfirmationDialog.Button.delete, systemImage: "trash", role: .destructive) {
                Task { await model.delete(installed.id) }
            }
        }
    }

    @ViewBuilder
    private var translatedPages: some View {
        if let bytes = model.translatedPagesBytes {
            LabeledContent {
                if model.isClearingTranslatedPages {
                    ProgressView()
                } else {
                    Text(bytes.byteText)
                }
            } label: {
                Text(Storage.pages).foregroundStyle(look.label)
            }
            Button(Storage.clearPages) { isConfirmingClear = true }
                .disabled(bytes == 0 || model.isClearingTranslatedPages)
                .confirmationDialog(
                    L10n.Localizable.ConfirmationDialog.Title.clear, isPresented: $isConfirmingClear,
                    titleVisibility: .visible
                ) {
                    Button(L10n.Localizable.ConfirmationDialog.Button.clear, role: .destructive) {
                        Task { await model.clearTranslatedPages() }
                    }
                }
        }
    }
}

/// The private store's address and access token (`README.md` section 5.6). Optional: what
/// is missing shows in the row (an address that cannot be a store, no token) and, when no
/// source offers the models at all, on the top card. The token is never shown back.
private struct PageTranslationSourceSection: View {
    @Bindable var model: PageTranslationSettingsModel

    private enum Field: Hashable {
        case address, token
    }

    @State private var token = ""
    @FocusState private var focus: Field?
    @Environment(\.look) private var look

    private typealias Source = L10n.Localizable.Settings.Translation.Source

    var body: some View {
        Section {
            addressRow
            tokenRow
        } header: {
            Text(L10n.Localizable.Settings.Translation.source).settingsSectionHeader()
        } footer: {
            Text(Source.footer).settingsFootnote()
        }
        .settingsRow()
        .onChange(of: focus) { previous, _ in
            switch previous {
            case .address: model.commitAddress()
            case .token: saveToken()
            case nil: break
            }
        }
        .onDisappear {
            model.commitAddress()
            saveToken()
        }
    }

    private var addressRow: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.xxSmall) {
            LabeledContent {
                TextField(Source.address, text: $model.addressDraft, prompt: Text(verbatim: "https://"))
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .multilineTextAlignment(.trailing)
                    .submitLabel(.done)
                    .focused($focus, equals: .address)
                    .onSubmit { model.commitAddress() }
            } label: {
                Text(Source.address).foregroundStyle(look.label)
            }
            if model.addressState == .invalid {
                // Inline, not a `Label`: a list puts a label's symbol in its icon column.
                Text("\(Image(systemName: "exclamationmark.triangle.fill")) \(Source.Address.invalid)")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
    }

    private var tokenRow: some View {
        LabeledContent {
            SecureField(
                Source.token, text: $token,
                prompt: model.hasToken ? Text(verbatim: "••••••••") : Text(L10n.Localizable.Struct.CookieValue.LocalizedString.none)
            )
            // VoiceOver would read the bullets of the prompt one by one.
            .accessibilityValue(model.hasToken && token.isEmpty ? Text(Source.Token.kept) : Text(verbatim: ""))
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .multilineTextAlignment(.trailing)
            .submitLabel(.done)
            .focused($focus, equals: .token)
            .onSubmit { saveToken() }
        } label: {
            Text(Source.token).foregroundStyle(look.label)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if model.hasToken {
                Button(L10n.Localizable.ConfirmationDialog.Button.delete, systemImage: "trash", role: .destructive) {
                    Task { await model.removeToken() }
                }
            }
        }
    }

    /// Keeps what was typed and empties the field: the token is never shown back.
    private func saveToken() {
        let typed = token
        guard !typed.isEmpty else { return }
        token = ""
        Task { await model.saveToken(typed) }
    }
}
