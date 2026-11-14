import EhModels
import SwiftUI

/// What a list's More menu offers: every list control of `Design/designs/README.md`
/// section 5.3 but the design's own `form`, which the design passes to the menu as a view.
///
/// A value, like the dock's content: the list computes it once per change of its model, and
/// the menu reports the chosen entry as a `ListMenuAction` for the list to perform. `nil` or
/// `false` leaves an entry out.
nonisolated struct ListMenuControls: Equatable, Sendable {
    /// The list's filter, when its source has one: "Filters" with the summary beneath.
    var filterSummary: FilterSummary?
    /// The order of a favourites list.
    var sort: ListMenuPicker?
    /// Toplists' period: Popular and the four periods, as the list offers them.
    var period: ListMenuPicker?
    /// Toplists' page.
    var page: ListMenuPage?
    /// Quick searches (Watched, favourites, search results).
    var quickSearch = false
    /// "Find in this list" (Front Page, Popular, Toplists, History).
    var find = false
    /// Clear History: `true` offers it, `false` shows it disabled (nothing to clear), `nil`
    /// leaves it out. The list asks for confirmation before it clears.
    var clear: Bool?
    var reload = false

    init(
        filterSummary: FilterSummary? = nil, sort: ListMenuPicker? = nil, period: ListMenuPicker? = nil,
        page: ListMenuPage? = nil, quickSearch: Bool = false, find: Bool = false, clear: Bool? = nil,
        reload: Bool = false
    ) {
        self.filterSummary = filterSummary
        self.sort = sort
        self.period = period
        self.page = page
        self.quickSearch = quickSearch
        self.find = find
        self.clear = clear
        self.reload = reload
    }
}

/// One choice among a few, shown as a submenu with the current one checked. Options are
/// identified by an `Int` the list maps back (a sort order's raw value, a period's index).
nonisolated struct ListMenuPicker: Equatable, Sendable {
    struct Option: Equatable, Sendable, Identifiable {
        let id: Int
        let title: String

        init(id: Int, title: String) {
            self.id = id
            self.title = title
        }
    }

    var title: String
    var systemImage: String
    var options: [Option]
    var selection: Int?

    init(title: String, systemImage: String, options: [Option], selection: Int?) {
        self.title = title
        self.systemImage = systemImage
        self.options = options
        self.selection = selection
    }
}

/// Where a paged list (Toplists) is: "Yesterday · page 1 of 200", Next, Previous, Jump.
nonisolated struct ListMenuPage: Equatable, Sendable {
    /// What is paged ("Yesterday"), named in the heading.
    var title: String
    var current: Int
    var maximum: Int

    init(title: String, current: Int, maximum: Int) {
        self.title = title
        self.current = current
        self.maximum = maximum
    }
}

nonisolated enum ListMenuAction: Hashable, Sendable {
    case filters
    case sort(Int)
    case period(Int)
    case nextPage
    case previousPage
    case jumpToPage
    case quickSearch
    case find
    case clear
    case reload
}

/// The trailing "More" menu in a list screen's top bar, the one place that always holds all of
/// its list controls (`README.md` section 5.3). The design puts it in a toolbar item and passes
/// its own form choices (Wall's densities, Ledger's covers) as `form`, which come after the
/// list's controls.
///
/// The menu's entries are built when it opens.
struct ListMoreMenu<Form: View>: View {
    private let controls: ListMenuControls
    private let perform: (ListMenuAction) -> Void
    private let form: Form

    init(
        controls: ListMenuControls, perform: @escaping (ListMenuAction) -> Void, @ViewBuilder form: () -> Form
    ) {
        self.controls = controls
        self.perform = perform
        self.form = form()
    }

    var body: some View {
        Menu {
            ListMoreMenuContent(controls: controls, perform: perform, form: form)
        } label: {
            Label(L10n.Localizable.List.Action.more, systemImage: "ellipsis")
        }
    }
}

extension ListMoreMenu where Form == EmptyView {
    init(controls: ListMenuControls, perform: @escaping (ListMenuAction) -> Void) {
        self.init(controls: controls, perform: perform) { EmptyView() }
    }
}

private struct ListMoreMenuContent<Form: View>: View {
    let controls: ListMenuControls
    let perform: (ListMenuAction) -> Void
    let form: Form

    var body: some View {
        Section {
            if let summary = controls.filterSummary {
                Button { perform(.filters) } label: {
                    Label {
                        Text(L10n.Localizable.ToolbarItem.Button.filters)
                        Text(summary.shortText)
                    } icon: {
                        Image(systemName: summary.isDefault ? "line.3.horizontal.decrease" : "line.3.horizontal.decrease.circle.fill")
                    }
                }
            }
            if let sort = controls.sort {
                picker(sort, action: ListMenuAction.sort)
            }
            if let period = controls.period {
                picker(period, action: ListMenuAction.period)
            }
        }
        if let page = controls.page {
            Section(L10n.Localizable.List.Page.menu(page.title, page.current, page.maximum)) {
                Button(L10n.Localizable.List.Page.next, systemImage: "chevron.forward") { perform(.nextPage) }
                    .disabled(page.current >= page.maximum)
                Button(L10n.Localizable.List.Page.previous, systemImage: "chevron.backward") { perform(.previousPage) }
                    .disabled(page.current <= 1)
                Button(L10n.Localizable.List.Page.jump, systemImage: "arrowshape.bounce.forward") { perform(.jumpToPage) }
                    .disabled(page.maximum <= 1)
            }
        }
        Section { form }
        Section {
            if controls.quickSearch {
                Button(L10n.Localizable.ToolbarItem.Button.quickSearch, systemImage: "magnifyingglass") {
                    perform(.quickSearch)
                }
            }
            if controls.find {
                Button(L10n.Localizable.List.find, systemImage: "text.magnifyingglass") { perform(.find) }
            }
            if controls.reload {
                Button(L10n.Localizable.ReadingView.ContextMenu.Button.reload, systemImage: "arrow.clockwise") {
                    perform(.reload)
                }
            }
        }
        if let canClear = controls.clear {
            Section {
                Button(L10n.Localizable.ConfirmationDialog.Button.clear, systemImage: "trash", role: .destructive) {
                    perform(.clear)
                }
                .disabled(!canClear)
            }
        }
    }

    private func picker(_ picker: ListMenuPicker, action: @escaping (Int) -> ListMenuAction) -> some View {
        Menu {
            ForEach(picker.options) { option in
                Toggle(
                    isOn: Binding(get: { option.id == picker.selection }, set: { _ in perform(action(option.id)) })
                ) {
                    Text(option.title)
                }
            }
        } label: {
            Label {
                Text(picker.title)
                if let selected = picker.options.first(where: { $0.id == picker.selection }) {
                    Text(selected.title)
                }
            } icon: {
                Image(systemName: picker.systemImage)
            }
        }
    }
}

extension FilterSummary {
    /// "8 of 10 · ★ 3+ · 20–200 pages": what the filter narrows, in the short form of Shelf's
    /// pill and the menu; the categories alone when nothing else is set.
    var shortText: String {
        summaryParts(categories: L10n.Localizable.List.Filter.summary(categoriesShown, Self.categoryCount))
    }

    /// "8 of 10 categories · ★ 3+": the long form of Ledger's subtitle.
    var longText: String {
        summaryParts(categories: L10n.Localizable.List.Filter.Summary.categories(categoriesShown, Self.categoryCount))
    }

    private func summaryParts(categories: String) -> String {
        var parts = [categories]
        if let minimumRating {
            parts.append(L10n.Localizable.List.Filter.minRating(minimumRating))
        }
        switch (minimumPages, maximumPages) {
        case let (lower?, upper?):
            parts.append(L10n.Localizable.List.Filter.Pages.range(lower, upper))
        case let (lower?, nil):
            parts.append(L10n.Localizable.List.Filter.Pages.atLeast(lower))
        case let (nil, upper?):
            parts.append(L10n.Localizable.List.Filter.Pages.range(1, upper))
        case (nil, nil):
            break
        }
        return parts.joined(separator: " · ")
    }
}
