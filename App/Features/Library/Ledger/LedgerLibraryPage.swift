import EhCore
import SwiftUI

/// The signed-in library: its title, the row for every folder at once, and the folder grid.
/// Each section reads only the stores it shows, so the counts arriving redraw two small
/// views and not the page.
struct LedgerLibraryPage: View {
    /// Off under `tabs`, where the Library tab draws the title above its switch.
    let showsTitle: Bool
    /// A folder's list; `-1` is every folder.
    let open: (Int) -> Void
    /// Pull to refresh: the folders' counts again.
    let refresh: () async -> Void

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if showsTitle {
                    LedgerLibraryTitle()
                        .padding(.horizontal, 20)
                        .padding(.bottom, 6)
                }
                LedgerLibraryAllRow { open(-1) }
                    .padding(.top, showsTitle ? 0 : 6)
                LedgerLibraryFolderGrid(open: open)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
            }
            .padding(.bottom, 24)
        }
        .refreshable { await refresh() }
        .ledgerLibraryBarTitle(isShown: showsTitle, isAlwaysVisible: false)
    }
}

/// Every folder at once: "All Favourites", and "1,284 in all" once the counts are known. A
/// 44 pt row of the Index's kind, its mark the neutral square of every folder.
private struct LedgerLibraryAllRow: View {
    let action: () -> Void

    @Environment(UserStore.self) private var userStore

    var body: some View {
        Button(action: action) {
            LedgerIndexLine(
                mark: .allFolders, title: L10n.Localizable.Library.All.title,
                value: userStore.favoriteTotalCount.map { L10n.Localizable.Start.Ledger.favoritesTotal($0.formatted()) }
            )
            .padding(.leading, 20)
            .padding(.trailing, 16)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        }
        .buttonStyle(LedgerIndexRowButtonStyle())
    }
}

/// The ten folders in cells of the Index's grid: two columns on a phone, as many as fit on a
/// wider screen, one at accessibility text sizes so the names stay readable.
private struct LedgerLibraryFolderGrid: View {
    let open: (Int) -> Void

    @Environment(UserStore.self) private var userStore
    @Environment(\.dynamicTypeSize) private var typeSize

    /// Two columns on every phone in portrait, from the narrowest (343 pt inside the margins)
    /// to the largest (398 pt); four to six on an iPad, where two would stretch a name and
    /// its count a foot apart.
    private static let fitting = [GridItem(.adaptive(minimum: 160), spacing: 6)]
    private static let oneColumn = [GridItem(.flexible())]

    var body: some View {
        LazyVGrid(columns: typeSize.isAccessibilitySize ? Self.oneColumn : Self.fitting, spacing: 6) {
            ForEach(userStore.ledgerIndexFolders) { folder in
                LedgerIndexFolderCell(folder: folder) { open(folder.index) }
            }
        }
    }
}
