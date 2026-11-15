import EhFeatures
import SwiftUI

/// The sheets of the search surface, presented by the surface for every design: Filters on
/// the set of the current scope, and the quick-search editor. A design asks for them with
/// `model.root.showFilters()` and `model.root.showQuickSearch()`.
struct SearchSurfaceSheets: ViewModifier {
    @Bindable var root: SearchRootModel
    let scope: SearchScope
    let controller: TagSearchFieldController

    func body(content: Content) -> some View {
        content
            .sheet(item: $root.sheet, onDismiss: searchPending) { sheet in
                switch sheet {
                case .filters:
                    // Favourites have no filters; their Filters button is not offered.
                    FiltersSheet(range: scope.filterRange ?? .search)
                case .quickSearch:
                    QuickSearchSheet(onSelect: root.selectQuickSearchWord)
                }
            }
            .sensoryFeedback(.impact(weight: .light), trigger: root.sheet) { _, new in new != nil }
    }

    /// A quick search chosen in the editor is searched in the field's scope once the sheet
    /// has gone, so the push does not race the dismissal.
    private func searchPending() {
        guard let keyword = root.takePendingSearch() else { return }
        controller.search(keyword)
    }
}
