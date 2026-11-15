import EhFeatures
import SwiftUI

/// Settings › Sign in: username / password over a wave background, plus the web login, on the
/// look's colours. The fields are filled cards (content, not glass); the button that signs in
/// is the one control on glass.
struct LoginScreen: View {
    @State private var model = LoginModel()
    @State private var loginTask: Task<Void, Never>?
    @FocusState private var focusedField: LoginModel.Field?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.look) private var look

    var body: some View {
        ZStack {
            look.surface.ignoresSafeArea()
            LoginBackground()
            VStack(spacing: Tokens.Spacing.large) {
                LoginField(
                    title: L10n.Localizable.LoginView.Title.username, text: $model.username,
                    field: .username, focusedField: $focusedField
                )
                LoginField(
                    title: L10n.Localizable.LoginView.Title.password, text: $model.password,
                    field: .password, focusedField: $focusedField
                )
                LoginButton(isLoading: model.loginState.isLoading, isDisabled: model.isLoginDisabled) {
                    run { await model.login() }
                }
                .padding(.top, Tokens.Spacing.xxLarge)
            }
            .frame(maxWidth: 360)
            .padding(.horizontal, Tokens.Spacing.xxLarge * 2)
        }
        .onSubmit { run { await model.submit() } }
        // Two-way sync between the model's focus decisions and the keyboard.
        .onChange(of: model.focusedField) { _, newValue in focusedField = newValue }
        .onChange(of: focusedField) { _, newValue in model.focusedField = newValue }
        .onChange(of: model.didLogin) { _, didLogin in
            if didLogin { dismiss() }
        }
        .onDisappear { loginTask?.cancel() }
        .sensoryFeedback(.impact(flexibility: .soft), trigger: model.attemptCount)
        .sensoryFeedback(.success, trigger: model.didLogin) { _, didLogin in didLogin }
        .sensoryFeedback(trigger: model.loginState) { _, state in
            state.failed == nil ? nil : .error
        }
        .animation(.default, value: model.loginState)
        .toolbar {
            if model.isWebLoginAvailable {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        model.presentWebLogin()
                    } label: {
                        Label(L10n.Localizable.LoginView.Title.login, systemImage: "globe")
                    }
                }
            }
        }
        .sheet(isPresented: isPresentingWebLogin) {
            if let url = model.webLoginURL {
                AccountWebView(url: url) { cookies in
                    model.webLoginDidFinish(cookies: cookies)
                }
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: model.webLoginURL) { _, new in new != nil }
        .navigationTitle(L10n.Localizable.LoginView.Title.login)
    }

    private var isPresentingWebLogin: Binding<Bool> {
        Binding(get: { model.webLoginURL != nil }, set: { if !$0 { model.webLoginURL = nil } })
    }

    private func run(_ operation: @escaping () async -> Void) {
        loginTask?.cancel()
        loginTask = Task { await operation() }
    }
}

private struct LoginBackground: View {
    @Environment(\.look) private var look

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                WaveForm(color: look.fill2, amplitude: 100, isReversed: true)
                WaveForm(color: look.fill, amplitude: 120)
            }
            .offset(y: proxy.size.height * 0.3)
            .drawingGroup()
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

private struct LoginField: View {
    let title: String
    @Binding var text: String
    let field: LoginModel.Field
    var focusedField: FocusState<LoginModel.Field?>.Binding

    @Environment(\.look) private var look

    private var isPassword: Bool { field == .password }

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.small) {
            Text(title)
                .font(.caption)
                .foregroundStyle(look.secondaryLabel)
                .accessibilityHidden(true)
            Group {
                if isPassword {
                    SecureField(title, text: $text, prompt: Text(verbatim: ""))
                } else {
                    TextField(title, text: $text, prompt: Text(verbatim: ""))
                }
            }
            .focused(focusedField, equals: field)
            .textContentType(isPassword ? .password : .username)
            .keyboardType(isPassword ? .asciiCapable : .default)
            .submitLabel(isPassword ? .done : .next)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .foregroundStyle(look.label)
            .padding(Tokens.Spacing.medium)
            .background(look.raised, in: .rect(cornerRadius: Tokens.Radius.field))
            .overlay {
                RoundedRectangle(cornerRadius: Tokens.Radius.field).strokeBorder(look.separator, lineWidth: 1)
            }
        }
    }
}

private struct LoginButton: View {
    let isLoading: Bool
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.forward")
                .font(.title.weight(.semibold))
                .frame(width: 64, height: 64)
                .opacity(isLoading ? 0 : 1)
                .overlay {
                    if isLoading { ProgressView() }
                }
        }
        .glassButtonStyle()
        .buttonBorderShape(.circle)
        .disabled(isDisabled || isLoading)
        .accessibilityLabel(L10n.Localizable.LoginView.Title.login)
    }
}
