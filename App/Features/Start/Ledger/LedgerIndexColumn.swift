import EhCore
import EhFeatures
import EhModels
import SwiftUI

/// The Index as the split view's sidebar on regular width (`ledger.md` section 2, iPad;
/// `spikes/S5.md` section 4): the system's sidebar list, which is glass on iOS 26 and the
/// standard sidebar on iOS 18, with the title (28), a smaller Continue card, the lists 36 pt
/// high, the folders as rows with All first, and the saved searches.
///
/// The lists and the folders are the column's selection: choosing one makes it the list
/// beside the column, and the one shown there gets the system's selection. A saved search is
/// pushed over that list.
struct LedgerIndexColumn: View {
    let model: LedgerIndexModel
    let navigation: LedgerIndexNavigation
    let editQuickSearches: () -> Void

    var body: some View {
        List(selection: selection) {
            Section {
                LedgerIndexTitle(isColumn: true)
                    .listRowSeparator(.hidden)
                LedgerIndexColumnContinue(navigation: navigation)
            }
            LedgerIndexColumnLists(model: model)
            LedgerIndexColumnFavorites(navigation: navigation)
            LedgerIndexColumnQuickSearches(model: model, navigation: navigation, edit: editQuickSearches)
        }
        .listStyle(.sidebar)
        .environment(\.defaultMinListRowHeight, 36)
        .refreshable { await model.folderCounts.refresh() }
        .ledgerIndexBarTitle()
    }

    /// The place at the bottom of the stack beside the column. Choosing a row goes through the
    /// router, so the selection always follows the path and never holds a state of its own.
    private var selection: Binding<LedgerIndexPlace?> {
        Binding(
            get: { LedgerIndexPlace(base: navigation.stack.path.first) },
            set: { place in
                if let place { navigation.choose(place) }
            }
        )
    }
}

// MARK: Sections

private struct LedgerIndexColumnContinue: View {
    let navigation: LedgerIndexNavigation

    @Environment(ContinueModel.self) private var continueModel
    @Environment(\.chrome) private var chrome

    var body: some View {
        // Beside the column the tab bar's accessory is off, so the card shows under both bars.
        if !chrome.continueIsInChrome, let item = continueModel.first {
            LedgerIndexContinueCard(item: item, isCompact: true) { navigation.continueReading(item) }
                // Content on the sidebar's glass: the card brings its own ground.
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
        }
    }
}

private struct LedgerIndexColumnLists: View {
    let model: LedgerIndexModel

    @Environment(FilterStore.self) private var filterStore
    @Environment(AccountSession.self) private var accountSession

    var body: some View {
        let items = LedgerIndexListItem.items(
            frontPage: FilterSummary(filterStore.globalFilter),
            watched: FilterSummary(filterStore.watchedFilter),
            isSignedIn: accountSession.isLoggedIn,
            historyCount: model.historyCount,
            // The column is narrow: as drawn, only History's count.
            showsFilters: false
        )
        Section {
            ForEach(items) { item in
                LedgerIndexLine(
                    mark: .symbol(item.kind.systemImage), title: item.kind.title, value: item.value,
                    showsChevron: false
                )
                .tag(LedgerIndexPlace.list(item.kind))
            }
        } header: {
            LedgerIndexSectionHeader(title: L10n.Localizable.Start.Ledger.lists)
        }
    }
}

/// The folders as rows, every folder first; signed out, one row that leads to signing in.
private struct LedgerIndexColumnFavorites: View {
    let navigation: LedgerIndexNavigation

    @Environment(UserStore.self) private var userStore
    @Environment(AccountSession.self) private var accountSession

    var body: some View {
        Section {
            if accountSession.isLoggedIn {
                LedgerIndexLine(
                    mark: .allFolders, title: L10n.Localizable.Library.all,
                    value: userStore.favoriteTotalCount?.formatted(), showsChevron: false
                )
                .tag(LedgerIndexPlace.folder(-1))
                ForEach(userStore.ledgerIndexFolders) { folder in
                    LedgerIndexLine(
                        mark: .folder(folder.index), title: folder.name, value: folder.count?.formatted(),
                        showsChevron: false
                    )
                    .tag(LedgerIndexPlace.folder(folder.index))
                }
            } else {
                Button(action: navigation.signIn) {
                    LedgerIndexLine(
                        mark: .symbol("person.crop.circle"), title: L10n.Localizable.Start.Ledger.signInFavorites,
                        showsChevron: false
                    )
                }
                .buttonStyle(.plain)
            }
        } header: {
            LedgerIndexSectionHeader(title: L10n.Localizable.Shell.Place.favorites)
        }
    }
}

private struct LedgerIndexColumnQuickSearches: View {
    let model: LedgerIndexModel
    let navigation: LedgerIndexNavigation
    let edit: () -> Void

    var body: some View {
        let words = model.quickSearches
        if !words.isEmpty {
            Section {
                ForEach(words) { word in
                    Button { navigation.run(word.content) } label: {
                        LedgerIndexLine(
                            mark: .symbol("magnifyingglass"), title: word.content,
                            value: word.name.isEmpty ? nil : word.name, isSyntax: true, showsChevron: false
                        )
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                LedgerIndexSectionHeader(title: L10n.Localizable.Start.Ledger.quickSearches) {
                    LedgerIndexEditButton(action: edit)
                }
            }
        }
    }
}
