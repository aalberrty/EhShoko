import Dependencies
import EhCore
import EhFeatures
import EhModels
import SwiftUI

/// The app once the launch is ready: the bar's switch point, with everything that is the
/// same under both bars attached above it (`Design/designs/README.md` section 4).
///
/// - It reads `designBar` and builds `TabsShell` or `CommandShell`; only the chosen one
///   exists. A change of the bar or of the first screen resets the navigation.
/// - The Settings sheet, the gallery sheet for links, the greeting, the reader opened from
///   Continue and the offer are attached above the switch, so they stay up when the bar
///   changes under them.
/// - It owns what every part shares and no part may own: the Continue model, and the one
///   zoom namespace, which the dock and the tab bar's accessory, outside every stack, need
///   as much as the screens do (`spikes/S4.md`).
struct ShellRoot: View {
    let model: AppModel

    @State private var continueModel = ContinueModel()
    @Namespace private var zoom
    @Environment(SettingsStore.self) private var settings

    // Shared services, created by the launch off the main actor. They are injected into the
    // environment so views read the individual properties they render; models reach the same
    // instances through `@Dependency`.
    @Dependency(\.filterStore) private var filterStore
    @Dependency(\.userStore) private var userStore
    @Dependency(\.tagTranslationService) private var tagTranslationService
    @Dependency(\.accountSession) private var accountSession

    var body: some View {
        let router = model.router
        bars
            .modifier(ShellPresentations(model: model, bar: settings.designBar))
            .modifier(ShellPlaceMemory(router: router))
            .onChange(of: settings.designBar) { router.resetNavigation() }
            .onChange(of: StartStructure.style(settings)) { router.resetNavigation() }
            .task { await continueModel.observe() }
            // TipKit's store is opened once the first screen is up, off the main actor, never
            // on the launch path; until then no tip shows (`TipsConfiguration`).
            .task { await TipsConfiguration.configure() }
            .environment(\.zoomNamespace, zoom)
            .environment(continueModel)
            .environment(filterStore)
            .environment(userStore)
            .environment(tagTranslationService)
            .environment(accountSession)
    }

    @ViewBuilder
    private var bars: some View {
        switch settings.designBar {
        case .tabs:
            TabsShell(model: model)
                .environment(\.chrome, ChromeContext(bar: .tabs))
        case .command:
            CommandShell(model: model)
                .environment(\.chrome, ChromeContext(bar: .command))
        }
    }
}

/// Remembers the place for Ledger's first screen, which reopens on it (`ledger.md`
/// section 2): the list the user is on, or none when they went back to the Index. Its own
/// modifier, so that a push or a pop runs this body and not the root's.
private struct ShellPlaceMemory: ViewModifier {
    let router: AppRouter

    @Environment(SettingsStore.self) private var settings

    func body(content: Content) -> some View {
        content.onChange(of: router.place) { _, place in
            ShellLaunch.remember(place, in: settings)
        }
    }
}

/// What the shell does with the place across launches.
enum ShellLaunch {
    /// Before the first screen exists: under Ledger's first screen, the list the user was on
    /// is put over the Index, so the Index is one Back away. Nothing is read from disk: the
    /// settings are already loaded for the first frame's colours.
    static func restorePlace(in router: AppRouter) {
        @Dependency(\.settings) var settings
        guard StartStructure.style(settings) == .ledger, let place = settings.lastPlace else { return }
        router.go(to: .list(place), start: .ledger)
    }

    static func remember(_ place: Place, in settings: SettingsStore) {
        guard StartStructure.style(settings) == .ledger else { return }
        let kind: GalleryListKind? = if case .list(let kind) = place { kind } else { nil }
        if settings.lastPlace != kind {
            settings.lastPlace = kind
        }
    }
}
