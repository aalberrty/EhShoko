import EhCore
import EhFeatures
import EhModels
import SwiftUI

/// The command bar: the place menu, the search field and one trailing control, three glass
/// shapes in the bottom chrome's container (`wall.md` section 1). Each shape is tagged with
/// its slot, which is what lets it turn into the dock's shape in the same slot.
///
/// A first working form, for task A2: plain, without the sideways swipe between places, the
/// sliding label or the symbol-only form for large text.
struct CommandBar: View {
    let router: AppRouter
    /// What the top screen put in the trailing circle, if anything.
    let control: BarControl?
    let perform: (BarAction) -> Void
    let openSearch: (SearchScope) -> Void

    @Environment(SettingsStore.self) private var settings
    @Environment(\.look) private var look
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        let start = StartStructure.style(settings)
        let place = router.place
        let search = CommandBarPlaces.search(top: router.home.path.last, place: place, start: start)
        HStack(spacing: ActionDock.spacing) {
            // On Ledger's Index the menu is not shown: the Index is the menu.
            if !(start == .ledger && place == .start && sizeClass != .regular) {
                placeMenu(place: place, start: start)
            }
            Button { openSearch(search.scope) } label: {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                    Text(search.text)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .font(.body)
                .foregroundStyle(look.secondaryLabel)
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, minHeight: ActionDock.height)
                .contentShape(.capsule)
            }
            .buttonStyle(.plain)
            .chromeShape(.centre, in: .capsule)
            trailing
        }
        .frame(height: ActionDock.height)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.Localizable.Shell.Bar.accessibility)
    }

    private func placeMenu(place: Place, start: DesignStyle) -> some View {
        Menu {
            Section {
                ForEach(CommandBarPlaces.entries(for: start), id: \.self) { entry in
                    Toggle(isOn: Binding(get: { entry == place }, set: { _ in router.go(to: entry, start: start) })) {
                        Label(entry.title(start: start), systemImage: entry.systemImage(start: start))
                    }
                }
            }
            Section {
                Button(L10n.Localizable.SettingView.Title.setting, systemImage: "gearshape") {
                    router.presentSettings()
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: place.systemImage(start: start))
                    .font(.title3)
                Text(place.title(start: start))
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(look.tertiaryLabel)
            }
            .foregroundStyle(look.label)
            // The field takes the width that is left, so the place's name keeps its own.
            .fixedSize()
            .padding(.horizontal, 14)
            .frame(height: ActionDock.height)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .chromeShape(.leading, in: .capsule)
    }

    @ViewBuilder
    private var trailing: some View {
        switch control {
        case .button(let systemImage, let title, let showsDot):
            Button { perform(.primary) } label: {
                symbol(systemImage)
                    .overlay(alignment: .topTrailing) {
                        if showsDot {
                            Circle()
                                .fill(.orange)
                                .frame(width: 8, height: 8)
                                .offset(x: -13, y: 13)
                        }
                    }
            }
            .buttonStyle(.plain)
            .chromeShape(.trailing, in: .circle)
            .accessibilityLabel(title)
        case .menu(let systemImage, let title, let controls):
            Menu {
                ListMenuEntries(controls: controls) { perform(.menu($0)) }
            } label: {
                symbol(systemImage)
            }
            .buttonStyle(.plain)
            .chromeShape(.trailing, in: .circle)
            .accessibilityLabel(title)
        case nil:
            EmptyView()
        }
    }

    private func symbol(_ systemImage: String) -> some View {
        Image(systemName: systemImage)
            .font(.title3)
            .foregroundStyle(look.label)
            .frame(width: ActionDock.height, height: ActionDock.height)
            .contentShape(.circle)
    }
}

/// What the place menu lists, and what the field says, for each first screen
/// (`README.md` section 5.1).
enum CommandBarPlaces {
    /// The menu's entries, in order. Wall's root is itself a list, so its first entry, Front
    /// Page, is `.start`; Shelf's and Ledger's is their first screen.
    static func entries(for start: DesignStyle) -> [Place] {
        let lists: [Place] = [.list(.popular), .list(.watched), .list(.toplists), .list(.history), .list(.favorites)]
        switch start {
        case .wall, .shelf: return [.start] + lists
        case .ledger: return [.start, .list(.frontpage)] + lists
        }
    }

    /// The scope the field opens the search surface on and what it reads: the keyword on a
    /// list of results, else the prompt for the scope of where the user is.
    static func search(top: Route?, place: Place, start: DesignStyle) -> (scope: SearchScope, text: String) {
        switch top {
        case .typedSearch(let keyword), .search(let keyword):
            return (.everywhere, keyword)
        case .listSearch(let scope, let keyword):
            return (scope, keyword)
        case .galleryList(.watched):
            return (.watched, L10n.Localizable.Shell.Search.Prompt.watched)
        case .galleryList(.favorites), .favoritesFolder:
            return (.favorites, L10n.Localizable.Shell.Search.Prompt.favorites)
        case .galleryList, .detail, .detailChild, .settings:
            return (.everywhere, L10n.Localizable.Shell.Search.prompt)
        case nil:
            switch place {
            case .list(.watched): return (.watched, L10n.Localizable.Shell.Search.Prompt.watched)
            case .list(.favorites): return (.favorites, L10n.Localizable.Shell.Search.Prompt.favorites)
            case .start where start == .ledger: return (.everywhere, L10n.Localizable.Shell.Search.Prompt.link)
            case .start, .list: return (.everywhere, L10n.Localizable.Shell.Search.prompt)
            }
        }
    }
}

extension Place {
    /// The place's name under the first screen `start`: the first screen has its own.
    func title(start: DesignStyle) -> String {
        switch self {
        case .list(let kind): kind.title
        case .start:
            switch start {
            case .shelf: L10n.Localizable.Shell.Place.home
            case .wall: GalleryListKind.frontpage.title
            case .ledger: L10n.Localizable.Shell.Place.index
            }
        }
    }

    func systemImage(start: DesignStyle) -> String {
        switch self {
        case .list(let kind): kind.systemImage
        case .start: start == .ledger ? "list.bullet" : "house"
        }
    }
}
