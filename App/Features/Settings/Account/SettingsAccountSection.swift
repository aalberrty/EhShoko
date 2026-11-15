import EhCore
import EhFeatures
import EhModels
import SwiftUI

/// The account card at the top of the Settings page: who is signed in, the site, and the
/// account's screens. It shows what is stored and never waits for the network.
struct SettingsAccountSection: View {
    @State private var model = AccountSettingModel()

    var body: some View {
        Section {
            // The card's head: no rule between the account and its site.
            SettingsAccountHeader(isSignedIn: model.isLoggedIn)
                .listRowSeparator(.hidden, edges: .bottom)
            HostPicker(selection: $model.galleryHost)
                .listRowSeparator(.hidden, edges: .top)
            if model.isLoggedIn {
                NavigationLink(value: Route.settings(.ehSetting)) {
                    SettingsRowLabel(symbol: "person.crop.circle", title: L10n.Localizable.Settings.Account.site)
                }
                cookiesRow
                SignOutRow(model: model)
            } else {
                NavigationLink(value: Route.settings(.login)) {
                    SettingsRowLabel(
                        symbol: "person.badge.key", title: L10n.Localizable.AccountSettingView.Button.login,
                        role: .tinted
                    )
                }
                cookiesRow
            }
        }
        .settingsRow()
    }

    private var cookiesRow: some View {
        NavigationLink(value: Route.settings(.account)) {
            SettingsRowLabel(symbol: "key", title: L10n.Localizable.Settings.Account.cookies)
        }
    }
}

/// The avatar, the name and the account's state.
private struct SettingsAccountHeader: View {
    let isSignedIn: Bool

    @Environment(UserStore.self) private var user
    @Environment(\.look) private var look

    private static let avatarSize: CGFloat = 56

    var body: some View {
        HStack(spacing: Tokens.Spacing.medium) {
            avatar
            VStack(alignment: .leading, spacing: Tokens.Spacing.xxSmall) {
                Text(title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(look.label)
                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(look.secondaryLabel)
                }
            }
        }
        .padding(.vertical, Tokens.Spacing.xSmall)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var avatar: some View {
        let size = Self.avatarSize
        if isSignedIn, let url = user.avatarURL {
            RemoteImage(url: url, size: CGSize(width: size, height: size), contentMode: .fill, cornerRadius: size / 2)
                .accessibilityHidden(true)
        } else {
            Image(systemName: "person.crop.circle")
                .font(.system(size: size * 0.5))
                .foregroundStyle(look.secondaryLabel)
                .frame(width: size, height: size)
                .background(look.fill, in: .circle)
                .accessibilityHidden(true)
        }
    }

    private var title: String {
        guard isSignedIn else { return L10n.Localizable.Settings.Account.signedOut }
        return user.displayName ?? L10n.Localizable.Settings.Account.signedIn
    }

    /// "Signed in · 356 credits", "Signed in" until the credits are known, or what an account
    /// is for while signed out.
    private var subtitle: String? {
        guard isSignedIn else { return L10n.Localizable.Settings.Account.SignedOut.body }
        if let credits = user.credits {
            return L10n.Localizable.Settings.Account.SignedIn.credits(credits)
        }
        return user.displayName == nil ? nil : L10n.Localizable.Settings.Account.signedIn
    }
}

/// E-Hentai or ExHentai: the site every request goes to.
private struct HostPicker: View {
    @Binding var selection: GalleryHost

    var body: some View {
        Picker(selection: $selection) {
            ForEach(GalleryHost.allCases) { host in
                Text(verbatim: host.rawValue).tag(host)
            }
        } label: {
            EmptyView()
        }
        .pickerStyle(.segmented)
    }
}

/// Sign out, after the existing confirmation.
private struct SignOutRow: View {
    @Bindable var model: AccountSettingModel

    var body: some View {
        Button {
            model.isConfirmingLogout = true
        } label: {
            SettingsRowLabel(
                symbol: "rectangle.portrait.and.arrow.right", title: L10n.Localizable.AccountSettingView.Button.logout,
                role: .destructive
            )
        }
        .confirmationDialog(
            L10n.Localizable.ConfirmationDialog.Title.logout,
            isPresented: $model.isConfirmingLogout,
            titleVisibility: .visible
        ) {
            Button(L10n.Localizable.ConfirmationDialog.Button.logout, role: .destructive) {
                Task { await model.logout() }
            }
        }
    }
}
