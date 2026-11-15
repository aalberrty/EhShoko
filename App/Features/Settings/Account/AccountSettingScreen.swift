import EhCore
import EhFeatures
import EhModels
import SwiftUI

/// Settings › Cookies: the login cookies of each site, editable and copyable. The site, sign in
/// and sign out are on the Settings page's account card.
struct AccountSettingScreen: View {
    @State private var model = AccountSettingModel()
    @State private var hud: HUDConfiguration?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Form {
            CookieSection(model: model, host: .ehentai, cookies: $model.ehCookies)
            CookieSection(model: model, host: .exhentai, cookies: $model.exCookies)
        }
        .settingsFormStyle()
        .navigationTitle(L10n.Localizable.Settings.Account.cookies)
        .hud($hud)
        .sensoryFeedback(.success, trigger: model.copyCount)
        .onChange(of: model.copyCount) { hud = .copiedToClipboard }
        // Loads on appear, and again when a login, logout or igneous fetch changed the cookies.
        .onChange(of: model.cookieRevision, initial: true) { model.syncCookies() }
        // Back, closing the sheet or backgrounding with a field still focused may not end its
        // editing.
        .onDisappear { model.commitPendingEdits() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { model.commitPendingEdits() }
        }
    }
}
