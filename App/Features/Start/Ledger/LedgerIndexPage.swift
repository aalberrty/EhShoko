import EhCore
import EhFeatures
import EhModels
import SwiftUI

/// The Index on a phone, and wherever it is the stack's root (`ledger.md` section 2,
/// `01-index-light`): one scroll of the title, the Continue card, the lists, the folders and
/// the saved searches. Each section reads only the stores it shows.
struct LedgerIndexPage: View {
    let model: LedgerIndexModel
    let navigation: LedgerIndexNavigation
    let editQuickSearches: () -> Void

    /// The bar shows the title once the Index's own has scrolled under it.
    @State private var showsBarTitle = false
    @Environment(\.look) private var look

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                LedgerIndexTitle(isColumn: false)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
                LedgerIndexPageContinue(navigation: navigation)
                LedgerIndexPageLists(model: model, navigation: navigation)
                LedgerIndexPageFavorites(navigation: navigation)
                LedgerIndexPageQuickSearches(model: model, navigation: navigation, edit: editQuickSearches)
            }
            .padding(.bottom, 24)
        }
        .background { look.background.ignoresSafeArea() }
        .refreshable { await model.refreshFolderCounts() }
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top > Self.titleScrollDistance
        } action: { _, isPast in
            showsBarTitle = isPast
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(L10n.Localizable.Shell.Place.index)
                    .font(.headline)
                    .lookTitleDesign()
                    .foregroundStyle(look.label)
                    .opacity(showsBarTitle ? 1 : 0)
                    .animation(.easeInOut(duration: 0.15), value: showsBarTitle)
                    .accessibilityHidden(!showsBarTitle)
            }
        }
    }

    /// About the height of the Index's own title.
    private static let titleScrollDistance: CGFloat = 40
}

// MARK: Sections

/// The Continue card, when something is in progress and the bar's chrome does not show it.
private struct LedgerIndexPageContinue: View {
    let navigation: LedgerIndexNavigation

    @Environment(ContinueModel.self) private var continueModel
    @Environment(\.chrome) private var chrome

    var body: some View {
        if !chrome.continueIsInChrome, let item = continueModel.first {
            LedgerIndexContinueCard(item: item, isCompact: false) { navigation.continueReading(item) }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 4)
        }
    }
}

private struct LedgerIndexPageLists: View {
    let model: LedgerIndexModel
    let navigation: LedgerIndexNavigation

    @Environment(FilterStore.self) private var filterStore
    @Environment(AccountSession.self) private var accountSession

    var body: some View {
        let items = LedgerIndexListItem.items(
            frontPage: FilterSummary(filterStore.globalFilter),
            watched: FilterSummary(filterStore.watchedFilter),
            isSignedIn: accountSession.isLoggedIn,
            historyCount: model.historyCount
        )
        LedgerIndexSectionHeader(title: L10n.Localizable.Start.Ledger.lists)
            .ledgerIndexPageHeader()
        ForEach(items) { item in
            LedgerIndexPageRow(isLast: item.kind == items.last?.kind) {
                navigation.open(item.kind)
            } label: {
                LedgerIndexLine(mark: .symbol(item.kind.systemImage), title: item.kind.title, value: item.value)
            }
        }
    }
}

/// The folders as a two-column grid with the total trailing the heading, or, signed out,
/// one row that leads to signing in.
private struct LedgerIndexPageFavorites: View {
    let navigation: LedgerIndexNavigation

    @Environment(UserStore.self) private var userStore
    @Environment(AccountSession.self) private var accountSession

    private static let columns = [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)]

    var body: some View {
        if accountSession.isLoggedIn {
            LedgerIndexSectionHeader(title: L10n.Localizable.Shell.Place.favorites) {
                Button(total) { navigation.openFolder(-1) }
                    .buttonStyle(.borderless)
            }
            .ledgerIndexPageHeader()
            LazyVGrid(columns: Self.columns, spacing: 6) {
                ForEach(userStore.ledgerIndexFolders) { folder in
                    LedgerIndexFolderCell(folder: folder) { navigation.openFolder(folder.index) }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 2)
        } else {
            LedgerIndexSectionHeader(title: L10n.Localizable.Shell.Place.favorites)
                .ledgerIndexPageHeader()
            LedgerIndexPageRow(isLast: true, action: navigation.signIn) {
                LedgerIndexLine(
                    mark: .symbol("person.crop.circle"), title: L10n.Localizable.Start.Ledger.signInFavorites
                )
            }
        }
    }

    /// "1,284 in all" once the counts are known; until then the way to every folder is "All".
    private var total: String {
        userStore.favoriteTotalCount.map { L10n.Localizable.Start.Ledger.favoritesTotal($0.formatted()) }
            ?? L10n.Localizable.Library.all
    }
}

/// The saved searches, absent when there are none.
private struct LedgerIndexPageQuickSearches: View {
    let model: LedgerIndexModel
    let navigation: LedgerIndexNavigation
    let edit: () -> Void

    var body: some View {
        let words = model.quickSearches
        if !words.isEmpty {
            LedgerIndexSectionHeader(title: L10n.Localizable.Start.Ledger.quickSearches) {
                LedgerIndexEditButton(action: edit)
            }
            .ledgerIndexPageHeader()
            ForEach(words) { word in
                LedgerIndexPageRow(isLast: word.id == words.last?.id) {
                    navigation.run(word.content)
                } label: {
                    LedgerIndexLine(
                        mark: .symbol("magnifyingglass"), title: word.content,
                        value: word.name.isEmpty ? nil : word.name, isSyntax: true
                    )
                }
            }
        }
    }
}

// MARK: Rows

/// A 44 pt row with a separator under it, inset to the text, except under the last.
private struct LedgerIndexPageRow<Label: View>: View {
    let isLast: Bool
    let action: () -> Void
    @ViewBuilder var label: Label

    @Environment(\.look) private var look

    var body: some View {
        Button(action: action) {
            label
                .padding(.leading, 20)
                .padding(.trailing, 16)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        }
        .buttonStyle(LedgerIndexRowButtonStyle())
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle()
                    .fill(look.separator)
                    .frame(height: 0.5)
                    // The symbol's column and its spacing: the rule starts under the text.
                    .padding(.leading, 57)
            }
        }
    }
}

private extension View {
    func ledgerIndexPageHeader() -> some View {
        padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 4)
    }
}
