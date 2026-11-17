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

    @Environment(\.look) private var look

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                LedgerTitle(L10n.Localizable.Shell.Place.index)
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
        .refreshable { await model.folderCounts.refresh() }
        .ledgerBarTitle(L10n.Localizable.Shell.Place.index)
    }
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
            historyCount: model.historyCount,
            showsFilters: true
        )
        LedgerIndexSectionHeader(title: L10n.Localizable.Start.Ledger.lists)
            .ledgerIndexPageHeader()
        ForEach(items) { item in
            LedgerIndexPageRow(isLast: item.kind == items.last?.kind) {
                navigation.open(item.kind)
            } label: {
                LedgerLine(mark: .symbol(item.kind.systemImage), title: item.kind.title, value: item.value)
            }
        }
    }
}

/// The folders as a two-column grid with the total trailing the heading, or, signed out,
/// one row that leads to signing in. At accessibility text sizes the grid is one column, so
/// the names stay readable.
private struct LedgerIndexPageFavorites: View {
    let navigation: LedgerIndexNavigation

    @Environment(UserStore.self) private var userStore
    @Environment(AccountSession.self) private var accountSession
    @Environment(\.dynamicTypeSize) private var typeSize

    private static let twoColumns = [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)]
    private static let oneColumn = [GridItem(.flexible())]

    var body: some View {
        if accountSession.isLoggedIn {
            LedgerIndexSectionHeader(title: L10n.Localizable.Shell.Place.favorites) {
                Button { navigation.openFolder(-1) } label: { Text(total).hitAreaOutset() }
                    .buttonStyle(.borderless)
                    .hitAreaOutsetReturned()
            }
            .ledgerIndexPageHeader()
            // One column from the largest standard size, where two cut folder names to a word.
            LazyVGrid(columns: typeSize >= .xxxLarge ? Self.oneColumn : Self.twoColumns, spacing: 6) {
                ForEach(userStore.libraryFolders) { folder in
                    LedgerFolderCell(folder: folder) { navigation.openFolder(folder.index) }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 2)
        } else {
            LedgerIndexSectionHeader(title: L10n.Localizable.Shell.Place.favorites)
                .ledgerIndexPageHeader()
            LedgerIndexPageRow(isLast: true, action: navigation.signIn) {
                LedgerLine(
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
                    LedgerLine(
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

    @ScaledMetric(relativeTo: .title3) private var markWidth = LedgerLine.markWidth

    @Environment(\.look) private var look

    var body: some View {
        Button(action: action) {
            label
                .padding(.leading, 20)
                .padding(.trailing, 16)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        }
        .buttonStyle(LedgerRowButtonStyle())
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle()
                    .fill(look.separator)
                    .frame(height: 0.5)
                    // The row's inset, the mark's column and its spacing: the rule starts
                    // under the text.
                    .padding(.leading, 20 + LedgerLine.markColumn(markWidth) + LedgerLine.markSpacing)
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
