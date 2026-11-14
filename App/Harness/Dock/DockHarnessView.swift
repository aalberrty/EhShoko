#if DEBUG
import Dependencies
import EhCore
import EhFeatures
import EhModels
import EhNetworking
import SwiftUI

/// The dock and the list chrome of `App/Features/GalleryList/Shared` before the shell exists:
/// a list of synthetic galleries with the long-press menu, the More menu and the find bar,
/// and the dock placed as the shell's bottom chrome will place it (an overlay on the stack, in
/// one glass container, over a screen that keeps the dock's height free).
///
/// Launched as the whole app with `-Harness dock`, and these arguments:
///
/// | Argument | Default | Meaning |
/// |---|---|---|
/// | `-HarnessLook shelf\|wall\|ledger` | `shelf` | The look. |
/// | `-HarnessScheme light\|dark` | the system's | The appearance. |
/// | `-HarnessPage dock\|states` | `dock` | The list with the dock, or the state pieces. |
/// | `-HarnessVariant shelf\|wall\|ledger\|comments\|bar` | the look's | What the dock holds; `bar` shows three bar shapes in the same slots, to see the morph. |
/// | `-HarnessFind YES` | NO | The find bar is open. |
/// | `-HarnessSheet YES` | NO | The dock is also shown in a sheet, where the pill's tint is checked. |
struct DockHarnessView: View {
    @State private var setup = DockHarnessSetup.atLaunch
    @State private var entries: [GalleryEntry] = []
    @State private var titleFilter = ""
    @State private var stack = StackRouter()
    @State private var appRouter = AppRouter()
    @State private var userStore = UserStore(defaults: UserDefaults(suiteName: "app.ehgaro.dock-harness") ?? .standard)
    /// Signed in with made-up cookies, so the menus show their favourite entries; nothing it
    /// sends reaches the site with them.
    @State private var actions = withDependencies {
        let storage = HTTPCookieStorage()
        let store = CookieStore(storage: storage)
        if let url = URL(string: "https://e-hentai.org/") {
            store.setOrEditCookie(for: url, name: CookieName.ipbMemberId, value: "1")
            store.setOrEditCookie(for: url, name: CookieName.ipbPassHash, value: "harness")
        }
        $0.cookieStore = store
    } operation: {
        GalleryActionsModel()
    }

    var body: some View {
        NavigationStack {
            DockHarnessPage(setup: $setup, entries: visibleEntries, actions: actions, titleFilter: $titleFilter)
        }
        .overlay(alignment: .bottom) {
            if setup.page == .dock {
                DockHarnessChrome(setup: $setup)
            }
        }
        .sheet(isPresented: $setup.showsSheet) {
            NavigationStack {
                DockHarnessPage(setup: $setup, entries: visibleEntries, actions: actions, titleFilter: $titleFilter)
            }
            .overlay(alignment: .bottom) { DockHarnessChrome(setup: $setup) }
            .presentationDetents([.medium, .large])
        }
        .environment(stack)
        .environment(appRouter)
        .environment(userStore)
        .galleryActionsFeedback(actions)
        .lookEnvironment(setup.look, accent: .systemBlue)
        .preferredColorScheme(setup.scheme)
        .task {
            ListHarnessURLProtocol.install()
            entries = await DockHarnessEntries.make()
        }
    }

    private var visibleEntries: [GalleryEntry] {
        titleFilter.isEmpty ? entries : entries.filter { $0.gallery.title.localizedCaseInsensitiveContains(titleFilter) }
    }
}

/// What the harness shows; the toolbar's menu changes it.
struct DockHarnessSetup: Equatable {
    enum Page: String, CaseIterable, Identifiable {
        case dock, states
        var id: String { rawValue }
    }

    enum Variant: String, CaseIterable, Identifiable {
        case shelf, wall, ledger, comments, bar
        var id: String { rawValue }
    }

    var look: Look
    var scheme: ColorScheme?
    var page: Page
    var variant: Variant
    var showsFind: Bool
    var showsSheet: Bool
    var isFavorite = false
    var progress: Int?

    static var atLaunch: DockHarnessSetup {
        let defaults = UserDefaults.standard
        let look: Look = switch defaults.string(forKey: "HarnessLook") {
        case "wall": .wall
        case "ledger": .ledger
        default: .shelf
        }
        let scheme: ColorScheme? = switch defaults.string(forKey: "HarnessScheme") {
        case "dark": .dark
        case "light": .light
        default: nil
        }
        let fallback: Variant = switch look {
        case .shelf: .shelf
        case .wall: .wall
        case .ledger: .ledger
        }
        return DockHarnessSetup(
            look: look, scheme: scheme,
            page: defaults.string(forKey: "HarnessPage").flatMap(Page.init(rawValue:)) ?? .dock,
            variant: defaults.string(forKey: "HarnessVariant").flatMap(Variant.init(rawValue:)) ?? fallback,
            showsFind: defaults.bool(forKey: "HarnessFind"),
            showsSheet: defaults.bool(forKey: "HarnessSheet"),
            progress: 23
        )
    }
}

/// Entries for 60 synthetic galleries, parsed off the main actor as a list page is mapped.
nonisolated private enum DockHarnessEntries {
    @concurrent
    static func make() async -> [GalleryEntry] {
        let galleries = await ListHarnessGalleries.make(count: 60, session: "dock", coverLatency: 0.05)
        return galleries.enumerated().map { index, gallery in
            GalleryEntry(gallery: gallery, favorite: index % 4 == 0 ? FavoriteMark(folder: index % 10) : nil)
        }
    }
}
#endif
