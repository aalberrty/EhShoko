import EhFeatures
import EhModels
import SwiftUI

// The states every list design shows (`Design/designs/README.md` section 5.3, item 5), in
// the look's colours. A design decides where each goes: the full-screen ones in place of its
// scroll view, never inside it, because their buttons are glass; the banner and the row
// inside the scroll view, where nothing is glass.

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
        if isScrolling {
            button.buttonStyle(.borderedProminent)
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
                    .glassButtonStyle()
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
                Button(L10n.Localizable.ErrorView.Button.retry, action: retry)
                    .glassProminentButtonStyle()
                Button(L10n.Localizable.List.Offline.history, action: openHistory)
                    .glassButtonStyle()
            }
            .buttonBorderShape(.capsule)
        } else {
            ErrorStateView(error: error, retry: error.isRetryable ? retry : nil)
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
            Button(L10n.Localizable.ErrorView.Button.retry, action: retry)
                .buttonStyle(.borderless)
                .fontWeight(.semibold)
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

    var body: some View {
        switch form {
        case .line(let text):
            HStack(spacing: Tokens.Spacing.small) {
                Image(systemName: "wifi.slash")
                    .foregroundStyle(look.secondaryLabel)
                Text(text ?? L10n.Localizable.List.Offline.title)
                    .foregroundStyle(look.label)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button(L10n.Localizable.ErrorView.Button.retry, action: retry)
                    .buttonStyle(.borderless)
                    .fontWeight(.semibold)
            }
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
}

extension AppError {
    /// Whether the request did not reach the site: the failure a list shows as offline when it
    /// already has rows.
    var isNetworkError: Bool {
        self == .networkingFailed
    }
}
