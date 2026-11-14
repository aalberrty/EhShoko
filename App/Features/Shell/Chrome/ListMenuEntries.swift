import EhModels
import SwiftUI

/// The entries of a menu of list controls, for a menu the shell opens itself: the command
/// bar's trailing circle when it is Sort or More. Built when the menu opens.
struct ListMenuEntries: View {
    let controls: ListMenuControls
    let perform: (ListMenuAction) -> Void

    var body: some View {
        Section {
            if controls.filterSummary != nil {
                Button(L10n.Localizable.FiltersView.Title.filters, systemImage: "line.3.horizontal.decrease") {
                    perform(.filters)
                }
            }
            if let sort = controls.sort {
                picker(sort) { .sort($0) }
            }
            if let period = controls.period {
                picker(period) { .period($0) }
            }
        }
        if let page = controls.page {
            Section("\(page.title) · \(page.current) / \(page.maximum)") {
                Button(L10n.Localizable.List.Page.next, systemImage: "chevron.right") { perform(.nextPage) }
                    .disabled(page.current >= page.maximum)
                Button(L10n.Localizable.List.Page.previous, systemImage: "chevron.left") { perform(.previousPage) }
                    .disabled(page.current <= 1)
                Button(L10n.Localizable.List.Page.jump, systemImage: "arrow.turn.down.right") {
                    perform(.jumpToPage)
                }
                .disabled(page.maximum <= 1)
            }
        }
        Section {
            if controls.quickSearch {
                Button(L10n.Localizable.SearchView.Section.Title.quickSearch, systemImage: "magnifyingglass") {
                    perform(.quickSearch)
                }
            }
            if controls.find {
                Button(L10n.Localizable.List.find, systemImage: "text.magnifyingglass") {
                    perform(.find)
                }
            }
            if controls.reload {
                Button(L10n.Localizable.ReadingView.ContextMenu.Button.reload, systemImage: "arrow.counterclockwise") {
                    perform(.reload)
                }
            }
            if let clear = controls.clear {
                Button(L10n.Localizable.ConfirmationDialog.Button.clear, systemImage: "trash", role: .destructive) {
                    perform(.clear)
                }
                .disabled(!clear)
            }
        }
    }

    private func picker(_ picker: ListMenuPicker, action: @escaping (Int) -> ListMenuAction) -> some View {
        Picker(
            picker.title, systemImage: picker.systemImage,
            selection: Binding(get: { picker.selection ?? -1 }, set: { perform(action($0)) })
        ) {
            ForEach(picker.options) { option in
                Text(option.title).tag(option.id)
            }
        }
        .pickerStyle(.menu)
    }
}
