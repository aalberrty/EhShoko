import EhFeatures
import EhModels
import SwiftUI

/// Edits the search filter of one `FilterRange` (legacy `FiltersView`), in Shelf's drawn layout
/// (`Design/designs/mockups/shelf/09-filters-dark.html`) on the look's tokens: Reset, the title
/// and Done in the bar; the set; the categories as tiles; one card for what narrows the results;
/// the other advanced options one push away.
///
/// Opens on the range of the list that presented it; legacy always opened on "Search". Every
/// change is saved as it is made, so Done only closes the sheet.
struct FiltersSheet: View {
    @State private var model: FiltersModel
    @FocusState private var focusedBound: FiltersModel.Bound?
    @Environment(\.dismiss) private var dismiss

    init(range: FilterRange) {
        _model = State(initialValue: FiltersModel(range: range))
    }

    var body: some View {
        NavigationStack {
            Form {
                FiltersRangeSection(model: model)
                FiltersCategorySection(model: model)
                FiltersNarrowingSection(model: model, focusedBound: $focusedBound)
            }
            .filtersFormStyle()
            .navigationTitle(L10n.Localizable.FiltersView.Title.filters)
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    FiltersResetButton(model: model)
                }
                ToolbarItem(placement: .confirmationAction) {
                    SheetConfirmButton { dismiss() }
                }
            }
        }
        // The model decides where focus goes on return; the field reports where the user taps.
        .onChange(of: model.focusedBound) { _, bound in
            if focusedBound != bound { focusedBound = bound }
        }
        .onChange(of: focusedBound) { _, bound in
            if model.focusedBound != bound { model.focusedBound = bound }
        }
    }
}

/// Resets the edited range after a confirmation, from the bar's leading side.
private struct FiltersResetButton: View {
    @Bindable var model: FiltersModel

    var body: some View {
        Button(L10n.Localizable.FiltersView.Button.resetFilters) {
            model.presentResetConfirmation()
        }
        .confirmationDialog(
            L10n.Localizable.ConfirmationDialog.Title.reset,
            isPresented: $model.isResetConfirmationPresented, titleVisibility: .visible
        ) {
            Button(L10n.Localizable.ConfirmationDialog.Button.reset, role: .destructive) { model.reset() }
        }
    }
}

/// Which of the three filters the sheet edits, as a segmented control on the sheet's ground.
private struct FiltersRangeSection: View {
    @Bindable var model: FiltersModel

    /// The drawing's order: the lists' filter, then Watched, then Search.
    private static let ranges: [FilterRange] = [.global, .watched, .search]

    var body: some View {
        Section {
            Picker(selection: $model.range) {
                ForEach(Self.ranges) { range in
                    Text(range.localizedName).tag(range)
                }
            } label: {
                EmptyView()
            }
            .pickerStyle(.segmented)
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets())
    }
}

#Preview {
    Color.clear.sheet(isPresented: .constant(true)) {
        FiltersSheet(range: .global)
    }
}
