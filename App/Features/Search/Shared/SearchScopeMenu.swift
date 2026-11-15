import EhFeatures
import SwiftUI

/// Wall's and Ledger's scope: a menu on the field's magnifier, beside the field in its
/// capsule (`spikes/S6.md` section 5). A SwiftUI menu rather than the field's left view: it
/// is the system's menu on both systems, opens upward from the bar on iOS 26, and choosing a
/// scope leaves the keyboard up and the field focused.
///
/// Signed out, Favourites and Watched are dimmed and say why.
struct SearchScopeMenu: View {
    @Bindable var model: SearchSurfaceModel

    @Environment(\.look) private var look

    var body: some View {
        Menu {
            Picker(selection: $model.scope) {
                ForEach(SearchScope.allCases, id: \.self) { scope in
                    option(scope).tag(scope)
                }
            } label: {
                EmptyView()
            }
        } label: {
            HStack(spacing: 2) {
                Image(systemName: "magnifyingglass")
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.bold))
            }
            .foregroundStyle(look.secondaryLabel)
            .frame(minWidth: 32, minHeight: 44)
            .contentShape(.rect)
            // Otherwise VoiceOver finds two images, "Search" and "Go Down", beside the button.
            .accessibilityHidden(true)
        }
        // There is no word for "scope" in the app's strings: the button says where the search
        // looks, as a pop-up button whose value is the place.
        .accessibilityLabel(L10n.Localizable.Shell.Search.prompt)
        .accessibilityValue(model.scope.localizedName)
    }

    @ViewBuilder
    private func option(_ scope: SearchScope) -> some View {
        if model.isAvailable(scope) {
            Label(scope.localizedName, systemImage: scope.systemImage)
        } else {
            Label {
                Text(scope.localizedName)
                Text(L10n.Localizable.Search.Scope.signin)
            } icon: {
                Image(systemName: scope.systemImage)
            }
            .selectionDisabled()
        }
    }
}
