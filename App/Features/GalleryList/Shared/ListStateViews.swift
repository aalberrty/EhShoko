import EhFeatures
import EhModels
import SwiftUI

// The states every list design shows (`Design/designs/README.md` section 5.3, item 5), in
// the look's colours. A design decides where each goes. In place of its scroll view their
// buttons are glass; a list that keeps a header above them (a first screen, the library)
// draws them as a row of its scroll view, under `statusActionForm(.filled)`, where the buttons
// are filled instead: glass is never in scrolling content (section 13). The banner and the
// next-page row are always inside the scroll view, and nothing in them is glass.

/// Signed out, on a list that needs an account (Watched, favourites): a symbol in a circle,
/// what the list is, a Sign In pill in the tint, "Use cookies instead", and what else needs an
/// account (`shelf/10-watched-signed-out-light`). Sign In opens Settings › Sign in
/// (`AppRouter.presentSignIn`), the link Settings › Cookies.
struct ListSignInState: View {
    enum Kind: Equatable, Sendable {
        case watched
        case favorites
    }

    let kind: Kind

    @Environment(AppRouter.self) private var appRouter
    @Environment(\.look) private var look
    @Environment(\.statusActionForm) private var actionForm
    @Environment(\.onTint) private var onTint
    @State private var requests = 0

    var body: some View {
        // Scrolls only when the text is too large to fit, and then without glass.
        ViewThatFits(in: .vertical) {
            content(isScrolling: false)
            ScrollView { content(isScrolling: true) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sensoryFeedback(.impact(flexibility: .soft), trigger: requests)
    }

    private func content(isScrolling: Bool) -> some View {
        VStack(spacing: Tokens.Spacing.large) {
            Image(systemName: kind == .watched ? "eye" : "heart")
                .font(.system(size: 32, weight: .medium))
                .foregroundStyle(look.secondaryLabel)
                .frame(width: 76, height: 76)
                .background(look.fill3, in: .circle)
                .accessibilityHidden(true)
            VStack(spacing: Tokens.Spacing.small) {
                Text(title)
                    .font(.title2.bold())
                    .fontDesign(look.titleDesign)
                    .foregroundStyle(look.label)
                if kind == .watched {
                    Text(L10n.Localizable.List.Signin.Watched.body)
                        .font(.subheadline)
                        .foregroundStyle(look.secondaryLabel)
                }
            }
            .multilineTextAlignment(.center)
            // ViewThatFits measures each choice at its ideal size; without this the
            // sentences would be measured, and drawn, on one line.
            .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: Tokens.Spacing.medium) {
                signInButton(isScrolling: isScrolling)
                Button(L10n.Localizable.List.Signin.cookies) { open([.settings(.account)]) }
                    .font(.subheadline)
            }
            Text(L10n.Localizable.List.Signin.note)
                .font(.footnote)
                .foregroundStyle(look.tertiaryLabel)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, Tokens.Spacing.xxLarge)
        .padding(.vertical, Tokens.Spacing.xLarge)
        .frame(maxWidth: 440)
    }

    @ViewBuilder
    private func signInButton(isScrolling: Bool) -> some View {
        let button = Button(action: signIn) {
            Text(L10n.Localizable.NotLoginView.Button.login)
                .font(.headline)
                .padding(.horizontal, Tokens.Spacing.xLarge)
        }
        .buttonBorderShape(.capsule)
        .controlSize(.large)
        if isScrolling || actionForm == .filled {
            // The style draws its label white, which vanishes on a light tint.
            button.buttonStyle(.borderedProminent).foregroundStyle(onTint)
        } else {
            button.glassProminentButtonStyle()
        }
    }

    private var title: String {
        switch kind {
        case .watched: L10n.Localizable.List.Signin.Watched.title
        case .favorites: L10n.Localizable.List.Signin.Favorites.title
        }
    }

    private func signIn() {
        requests += 1
        appRouter.presentSignIn()
    }

    private func open(_ path: [Route]) {
        requests += 1
        appRouter.presentSettings(path)
    }
}

/// Nothing in the list: a symbol, "No galleries" (Ledger: "Nothing here yet"), and "Filters"
/// when the list's filter narrows something.
struct ListEmptyState: View {
    private let message: String
    private let filters: (() -> Void)?
    @Environment(\.look) private var look
    @Environment(\.statusActionForm) private var actionForm

    /// - Parameter filters: opens Filters; pass it only when the filter is not the default.
    init(message: String = L10n.Localizable.List.empty, filters: (() -> Void)? = nil) {
        self.message = message
        self.filters = filters
    }

    var body: some View {
        ContentUnavailableView {
            Label {
                Text(message)
                    .fontDesign(look.titleDesign)
                    .foregroundStyle(look.label)
            } icon: {
                Image(systemName: "square.stack.3d.up.slash")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(look.tertiaryLabel)
            }
        } actions: {
            if let filters {
                FiltersButton(action: filters)
                    .statusSecondaryButtonStyle(actionForm)
                    .buttonBorderShape(.capsule)
            }
        }
    }
}

/// The first page failed: the shared error view with Retry and, when the design offers it and
/// the error is a network error, "Open History" (Wall).
struct ListFailedState: View {
    private let error: AppError
    private let retry: () -> Void
    private let openHistory: (() -> Void)?
    @Environment(\.look) private var look
    @Environment(\.statusActionForm) private var actionForm
    @Environment(\.onTint) private var onTint

    init(error: AppError, retry: @escaping () -> Void, openHistory: (() -> Void)? = nil) {
        self.error = error
        self.retry = retry
        self.openHistory = openHistory
    }

    var body: some View {
        if let openHistory, error.isNetworkError {
            ContentUnavailableView {
                Label {
                    if let headline = error.headline {
                        Text(headline).fontDesign(look.titleDesign).foregroundStyle(look.label)
                    }
                } icon: {
                    Image(systemName: error.symbol.rawValue)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(look.tertiaryLabel)
                }
            } description: {
                Text(error.alertText).foregroundStyle(look.secondaryLabel)
            } actions: {
                retryButton
                Button(L10n.Localizable.List.Offline.history, action: openHistory)
                    .statusSecondaryButtonStyle(actionForm)
            }
            .buttonBorderShape(.capsule)
        } else {
            ErrorStateView(error: error, retry: error.isRetryable ? retry : nil)
        }
    }

    @ViewBuilder
    private var retryButton: some View {
        let button = Button(L10n.Localizable.ErrorView.Button.retry, action: retry)
        switch actionForm {
        case .glass:
            button.glassProminentButtonStyle()
        case .filled:
            // The style draws its label white, which vanishes on a light tint.
            button.buttonStyle(.borderedProminent).foregroundStyle(onTint)
        }
    }
}

/// The next page failed: a row at the end of the list, "Couldn't load more · Retry". It sits
/// in the scroll view, so nothing in it is glass.
struct ListLoadMoreFailedRow: View {
    let retry: () -> Void
    @Environment(\.look) private var look

    var body: some View {
        HStack(spacing: Tokens.Spacing.small) {
            Text(L10n.Localizable.List.More.failed)
                .foregroundStyle(look.secondaryLabel)
            Text(verbatim: "·")
                .foregroundStyle(look.tertiaryLabel)
                .accessibilityHidden(true)
            Button(action: retry) {
                Text(L10n.Localizable.ErrorView.Button.retry).hitAreaOutset()
            }
            .buttonStyle(.borderless)
            .fontWeight(.semibold)
            .hitAreaOutsetReturned()
        }
        .font(.subheadline)
        .frame(maxWidth: .infinity, minHeight: 50)
        .accessibilityElement(children: .combine)
    }
}

/// Offline with rows already shown: a banner above the first row that keeps the rows visible.
/// It scrolls with them, so nothing in it is glass.
struct ListOfflineBanner: View {
    enum Form: Equatable, Sendable {
        /// One line and Retry: "You're offline" (Shelf, `nil`), or the text given: "Offline ·
        /// showing what was loaded" (Ledger, `List.Offline.short`).
        case line(String?)
        /// A card with the explanation and a Retry pill, on the surface mixed with orange (Wall).
        case card
    }

    let form: Form
    let retry: () -> Void
    @Environment(\.look) private var look
    @Environment(\.onTint) private var onTint
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        switch form {
        case .line(let text):
            line(text ?? L10n.Localizable.List.Offline.title)
                .font(.subheadline)
                .padding(.horizontal, Tokens.Spacing.medium)
                .frame(minHeight: 40)
                .background(look.surface, in: .rect(cornerRadius: Tokens.Radius.chip, style: .continuous))
        case .card:
            VStack(alignment: .leading, spacing: Tokens.Spacing.small) {
                Label(L10n.Localizable.List.Offline.title, systemImage: "wifi.slash")
                    .font(.headline)
                    .foregroundStyle(look.label)
                Text(L10n.Localizable.List.Offline.body)
                    .font(.subheadline)
                    .foregroundStyle(look.secondaryLabel)
                    .fixedSize(horizontal: false, vertical: true)
                Button(action: retry) {
                    Text(L10n.Localizable.ErrorView.Button.retry)
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, Tokens.Spacing.large)
                        .padding(.vertical, Tokens.Spacing.small)
                        .background(.tint, in: .capsule)
                        .foregroundStyle(onTint)
                }
                .buttonStyle(.plain)
                .padding(.top, Tokens.Spacing.xSmall)
            }
            .padding(Tokens.Spacing.large)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: Tokens.Radius.chip * 1.5, style: .continuous)
                    .fill(look.surface)
                    .overlay {
                        RoundedRectangle(cornerRadius: Tokens.Radius.chip * 1.5, style: .continuous)
                            .fill(Color.orange.opacity(0.16))
                    }
            }
        }
    }

    /// The symbol, the text and Retry on one line; at the accessibility text sizes Retry goes
    /// under the text, which would otherwise be squeezed to a word a line.
    @ViewBuilder
    private func line(_ text: String) -> some View {
        let symbol = Image(systemName: "wifi.slash")
            .foregroundStyle(look.secondaryLabel)
            // The text says it; VoiceOver would read the symbol as "Wi-Fi Off" first.
            .accessibilityHidden(true)
        let retryButton = Button(action: retry) {
            Text(L10n.Localizable.ErrorView.Button.retry).hitAreaOutset()
        }
        .buttonStyle(.borderless)
        .fontWeight(.semibold)
        .hitAreaOutsetReturned()
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: Tokens.Spacing.xSmall) {
                HStack(alignment: .firstTextBaseline, spacing: Tokens.Spacing.small) {
                    symbol
                    Text(text)
                        .foregroundStyle(look.label)
                        .fixedSize(horizontal: false, vertical: true)
                }
                retryButton
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, Tokens.Spacing.small)
        } else {
            HStack(spacing: Tokens.Spacing.small) {
                symbol
                Text(text)
                    .foregroundStyle(look.label)
                    .frame(maxWidth: .infinity, alignment: .leading)
                retryButton
            }
        }
    }
}

private extension View {
    /// A state's second button: glass where the state stands alone, a tinted fill in scrolling
    /// content.
    @ViewBuilder
    func statusSecondaryButtonStyle(_ form: StatusActionForm) -> some View {
        switch form {
        case .glass: glassButtonStyle()
        case .filled: buttonStyle(.bordered)
        }
    }
}

extension AppError {
    /// Whether the request did not reach the site: the failure a list shows as offline when it
    /// already has rows.
    var isNetworkError: Bool {
        self == .networkingFailed
    }
}
