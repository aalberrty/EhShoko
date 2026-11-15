import SwiftUI

extension View {
    /// "Find in this list" (`Design/designs/README.md` section 5.3): while `isPresented`, a
    /// field pinned above the rows, under the navigation bar, that filters the loaded titles
    /// through `text` (the list model's title filter, as v3's search field did). Closing it
    /// clears the text.
    ///
    /// The bar is always attached and only its content comes and goes, so opening it keeps the
    /// list, its scroll position and its state. It is a control above content, so on iOS 26
    /// its field and close button are glass, in the pinned top bar where the navigation bar's
    /// scroll edge carries on behind them (`README.md` section 13); on iOS 18 they are material
    /// shapes on the bar material.
    func listFindBar(isPresented: Binding<Bool>, text: Binding<String>) -> some View {
        modifier(ListFindBarModifier(isPresented: isPresented, text: text))
    }
}

private struct ListFindBarModifier: ViewModifier {
    @Binding var isPresented: Bool
    @Binding var text: String

    func body(content: Content) -> some View {
        content
            .topBar(isPresented: isPresented, spacing: 0) {
                ListFindBar(text: $text) {
                    text = ""
                    isPresented = false
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            .animation(.smooth(duration: 0.3), value: isPresented)
    }
}

/// The find field and its close button. Focused when it appears.
struct ListFindBar: View {
    @Binding var text: String
    let close: () -> Void

    @FocusState private var isFocused: Bool
    @Environment(\.look) private var look

    private static let height: CGFloat = 40

    var body: some View {
        GlassGroup(spacing: Tokens.Spacing.small) {
            HStack(spacing: Tokens.Spacing.small) {
                field
                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.body.weight(.medium))
                        .foregroundStyle(look.label)
                        .frame(width: Self.height, height: Self.height)
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .glassSurface(in: .circle, isInteractive: true)
                // The symbol carries the system's localized "Close" for VoiceOver.
            }
        }
        .padding(.horizontal, Tokens.Spacing.large)
        .padding(.vertical, Tokens.Spacing.small)
        .onAppear { isFocused = true }
    }

    private var field: some View {
        HStack(spacing: Tokens.Spacing.small) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(look.secondaryLabel)
            TextField(text: $text, prompt: Text(L10n.Localizable.Searchable.Prompt.filter)) {
                Text(L10n.Localizable.List.find)
            }
            .focused($isFocused)
            .submitLabel(.search)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .onSubmit { isFocused = false }
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(look.tertiaryLabel)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.Localizable.ConfirmationDialog.Button.clear)
            }
        }
        .padding(.horizontal, Tokens.Spacing.medium)
        .frame(height: Self.height)
        .glassSurface(in: .capsule, isInteractive: true)
    }
}
