import EhCore
import EhFeatures
import EhModels
import SwiftUI

/// What a Ledger list puts in its screen's top bar (`ledger.md` section 3): a centred inline
/// title in the look's title face with a subtitle under it, and, trailing, the covers toggle
/// and More. Under a first screen's header the screen draws the title, and the list keeps only
/// its trailing items.
///
/// The subtitle says what the list is narrowed to: the filter in words ("8 of 10 categories ·
/// ★ 3+"), or for favourites the count and the order. Where the bar does not hold the list's
/// primary control (under `tabs`), the subtitle is that control: it opens Filters, or is the
/// order's menu. Toplists' period is a menu on the title, its page a menu in the subtitle's
/// place. "Find in this list" shows the find field under the bar.
struct LedgerListChrome: ViewModifier {
    let input: ListDesignInput
    @Binding var showsCovers: Bool

    @Environment(\.look) private var look
    @Environment(\.lookTint) private var tint

    func body(content: Content) -> some View {
        content
            .modifier(LedgerListTitleItems(input: input, isShown: !input.context.embedsInStart))
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { showsCovers.toggle() } label: {
                        Label(coversTitle, systemImage: "eye.slash")
                    }
                    // In the tint while covers are off.
                    .foregroundStyle(showsCovers ? look.label : tint)
                    ListMoreMenu(controls: input.controls.menu, perform: input.perform) {
                        Button(coversTitle, systemImage: showsCovers ? "eye.slash" : "eye") {
                            showsCovers.toggle()
                        }
                    }
                }
            }
            .listFindBar(isPresented: isFinding, text: findText)
    }

    private var coversTitle: String {
        showsCovers ? L10n.Localizable.List.Covers.hide : L10n.Localizable.List.Covers.show
    }

    private var isFinding: Binding<Bool> {
        let input = input
        return Binding(
            get: { input.controls.isFinding },
            set: { isShown in
                // `.find` toggles; the wrapper clears the text when it closes.
                if isShown != input.controls.isFinding { input.perform(.find) }
            }
        )
    }

    private var findText: Binding<String> {
        let feed = input.feed
        return Binding(get: { feed.findText }, set: { feed.findText = $0 })
    }
}

/// The title and subtitle, as the bar's principal item, when the list has its own screen.
private struct LedgerListTitleItems: ViewModifier {
    let input: ListDesignInput
    let isShown: Bool

    @Environment(\.chrome) private var chrome
    @Environment(UserStore.self) private var userStore

    func body(content: Content) -> some View {
        if isShown {
            content
                // For Back and the app switcher; the principal item draws it on screen.
                .navigationTitle(input.context.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        LedgerListTitle(
                            title: input.context.title, controls: input.controls, subtitle: subtitle,
                            barHoldsPrimaryControl: chrome.barHoldsPrimaryControl, perform: input.perform
                        )
                    }
                }
        } else {
            content
        }
    }

    /// The filter in words, or the favourites' count and order; `nil` for neither.
    private var subtitle: String? {
        switch input.controls.primary {
        case .filter(let summary):
            return summary.isDefault ? nil : summary.longText
        case .sort(let sort):
            var parts = [String]()
            if let count = folderCount {
                parts.append(count.formatted())
            }
            if let order = Self.order(of: sort) {
                parts.append(order)
            }
            return parts.isEmpty ? nil : parts.joined(separator: " · ")
        case nil:
            return nil
        }
    }

    /// How many galleries the folder holds, as the last favourites page said.
    private var folderCount: Int? {
        guard case .folder(let folder) = input.context.kind else { return nil }
        return folder == -1 ? userStore.favoriteTotalCount : userStore.favoriteFolderCounts[folder]
    }

    /// "newest favourited first" or "newest posted first". The sort's options are the site's
    /// orders, by index.
    private static func order(of sort: ListMenuPicker) -> String? {
        let orders = EhSetting.FavoritesSortOrder.allCases
        guard let selection = sort.selection, orders.indices.contains(selection) else { return nil }
        switch orders[selection] {
        case .favoritedTime: return L10n.Localizable.Library.Order.favorited
        case .lastUpdateTime: return L10n.Localizable.Library.Order.posted
        }
    }
}

/// The principal item: the title, or Toplists' period menu, over the subtitle, the page menu,
/// or under `tabs` the primary control.
private struct LedgerListTitle: View {
    let title: String
    let controls: ListControls
    let subtitle: String?
    let barHoldsPrimaryControl: Bool
    let perform: (ListMenuAction) -> Void

    @Environment(\.look) private var look

    var body: some View {
        VStack(spacing: 0) {
            titleLine
            subtitleLine
                .font(.caption)
                .foregroundStyle(look.secondaryLabel)
        }
        .lineLimit(1)
        .multilineTextAlignment(.center)
    }

    @ViewBuilder
    private var titleLine: some View {
        if let period = controls.menu.period {
            Menu {
                choices(period, action: ListMenuAction.period)
            } label: {
                HStack(spacing: 4) {
                    Text(Self.joined(title, period.selectedTitle))
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(look.secondaryLabel)
                }
                .font(.headline)
                .fontDesign(look.titleDesign)
                .foregroundStyle(look.label)
            }
        } else {
            Text(title)
                .font(.headline)
                .fontDesign(look.titleDesign)
                .foregroundStyle(look.label)
                .accessibilityAddTraits(.isHeader)
        }
    }

    @ViewBuilder
    private var subtitleLine: some View {
        if let page = controls.menu.page {
            Menu {
                Button(L10n.Localizable.List.Page.next, systemImage: "chevron.forward") { perform(.nextPage) }
                    .disabled(page.current >= page.maximum)
                Button(L10n.Localizable.List.Page.previous, systemImage: "chevron.backward") { perform(.previousPage) }
                    .disabled(page.current <= 1)
                Button(L10n.Localizable.List.Page.jump, systemImage: "arrowshape.bounce.forward") { perform(.jumpToPage) }
                    .disabled(page.maximum <= 1)
            } label: {
                HStack(spacing: 3) {
                    Text(L10n.Localizable.List.Page.divider(page.current))
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.bold))
                }
            }
        } else if !barHoldsPrimaryControl, case .filter = controls.primary {
            Button { perform(.filters) } label: {
                Text(subtitle ?? L10n.Localizable.FiltersView.Title.filters)
            }
            .buttonStyle(.plain)
        } else if !barHoldsPrimaryControl, case .sort(let sort) = controls.primary {
            Menu {
                choices(sort, action: ListMenuAction.sort)
            } label: {
                HStack(spacing: 3) {
                    Text(subtitle ?? sort.title)
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.bold))
                }
            }
        } else if let subtitle {
            Text(subtitle)
        }
    }

    private func choices(_ picker: ListMenuPicker, action: @escaping (Int) -> ListMenuAction) -> some View {
        ForEach(picker.options) { option in
            Toggle(isOn: Binding(get: { option.id == picker.selection }, set: { _ in perform(action(option.id)) })) {
                Text(option.title)
            }
        }
    }

    private static func joined(_ title: String, _ choice: String?) -> String {
        guard let choice, choice != title else { return title }
        return title + " · " + choice
    }
}

private extension ListMenuPicker {
    var selectedTitle: String? {
        options.first { $0.id == selection }?.title
    }
}
