import EhFeatures
import EhModels
import SwiftUI

// What Wall's list draws besides its covers (`wall.md` section 3, "States" and "List
// controls"). Everything here scrolls with the covers, so nothing in it is glass.

/// Signed out, empty or failed: the shared state views, in place of the covers. A failed
/// first page also offers History when the site could not be reached, since what was read
/// still opens.
struct WallListState: View {
    let input: ListDesignInput

    @Environment(StackRouter.self) private var stack

    var body: some View {
        switch input.feed.phase {
        case .signedOut(let kind):
            ListSignInState(kind: kind)
        case .empty:
            ListEmptyState(filters: filters)
        case .failed(let error):
            ListFailedState(error: error, retry: { input.feed.retry() }, openHistory: openHistory)
        case .loading, .content:
            EmptyView()
        }
    }

    /// The states that take the list's place, under its header if it has one: everything but
    /// covers and their placeholders.
    static func replacesList(_ phase: ListFeed.Phase) -> Bool {
        switch phase {
        case .signedOut, .empty, .failed: true
        case .loading, .content: false
        }
    }

    /// "Filters" when the list's filter narrows something.
    private var filters: (() -> Void)? {
        guard let summary = input.controls.menu.filterSummary, !summary.isDefault else { return nil }
        let perform = input.perform
        return { perform(.filters) }
    }

    /// History is pushed on the list's own stack, which works under either bar.
    private var openHistory: (() -> Void)? {
        guard input.context.kind != .place(.history) else { return nil }
        let stack = stack
        return { stack.push(.galleryList(.history)) }
    }
}

/// What stands between the header and the covers, as one item that spans the columns:
/// Toplists' period and page menus, the list's primary control where the bar does not hold
/// it, and the offline banner. With none of them it has no height.
struct WallListTop: View {
    let input: ListDesignInput
    /// The filter pill or the sort menu; `nil` where the bar holds it, a first screen draws the
    /// list's heading, or the list cannot be shown.
    let primary: ListPrimaryControl?

    var body: some View {
        let menu = input.controls.menu
        let feed = input.feed
        let isOffline = feed.phase == .content && feed.staleError?.isNetworkError == true
        VStack(alignment: .leading, spacing: 0) {
            if menu.period != nil || menu.page != nil || primary != nil {
                HStack(spacing: 8) {
                    if let period = menu.period {
                        WallListPickerMenu(picker: period) { input.perform(.period($0)) }
                    }
                    if let page = menu.page {
                        WallListPageMenu(page: page, perform: input.perform)
                    }
                    switch primary {
                    case .filter(let summary):
                        WallListFilterPill(summary: summary) { input.perform(.filters) }
                    case .sort(let picker):
                        WallListPickerMenu(picker: picker) { input.perform(.sort($0)) }
                    case nil:
                        EmptyView()
                    }
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 10)
            }
            if isOffline {
                // Under a first screen's header (Continue), right above the covers it is about.
                ListOfflineBanner(form: .card) { feed.retry() }
                    .padding(.bottom, 10)
            }
        }
        // Under the list's own top bar the covers keep the wall's margin from it; under a
        // first screen's header they follow it directly.
        .padding(.top, input.context.heading == .header ? 0 : WallGridLayout.margin)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A control that scrolls with the covers: a capsule on a fill from the look, 34 high.
private struct WallListPill<Label: View>: View {
    @ViewBuilder var label: Label

    @Environment(\.look) private var look

    var body: some View {
        HStack(spacing: 5) { label }
            .font(.subheadline.weight(.semibold))
            .lineLimit(1)
            .foregroundStyle(look.label)
            .padding(.horizontal, 13)
            .frame(minHeight: 34)
            .background(look.fill3, in: .capsule)
            .contentShape(.capsule)
    }
}

/// "Yesterday ⌄", or a favourites folder's order: a menu of the list's choices with the
/// current one checked.
private struct WallListPickerMenu: View {
    let picker: ListMenuPicker
    let choose: (Int) -> Void

    @Environment(\.look) private var look

    var body: some View {
        Menu {
            ForEach(picker.options) { option in
                Toggle(isOn: Binding(get: { option.id == picker.selection }, set: { _ in choose(option.id) })) {
                    Text(option.title)
                }
            }
        } label: {
            WallListPill {
                Text(picker.options.first { $0.id == picker.selection }?.title ?? picker.title)
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(look.secondaryLabel)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(picker.title)
    }
}

/// "Page 1 ⌄": where a numbered list is, with Next, Previous and Jump to page. The same
/// entries are in the More menu.
private struct WallListPageMenu: View {
    let page: ListMenuPage
    let perform: (ListMenuAction) -> Void

    @Environment(\.look) private var look

    var body: some View {
        Menu {
            Section(L10n.Localizable.List.Page.menu(page.title, page.current, page.maximum)) {
                Button(L10n.Localizable.List.Page.next, systemImage: "chevron.forward") { perform(.nextPage) }
                    .disabled(page.current >= page.maximum)
                Button(L10n.Localizable.List.Page.previous, systemImage: "chevron.backward") { perform(.previousPage) }
                    .disabled(page.current <= 1)
                Button(L10n.Localizable.List.Page.jump, systemImage: "arrowshape.bounce.forward") { perform(.jumpToPage) }
                    .disabled(page.maximum <= 1)
            }
        } label: {
            WallListPill {
                Text(L10n.Localizable.List.Page.divider(page.current))
                    .monospacedDigit()
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(look.secondaryLabel)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.Localizable.List.Page.menu(page.title, page.current, page.maximum))
    }
}

/// The filter where the bar does not hold it: "8 of 10 · ★ 3+" with the filter symbol, filled
/// while the filter is not the default. It opens Filters.
private struct WallListFilterPill: View {
    let summary: FilterSummary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            WallListPill {
                Image(systemName: "line.3.horizontal.decrease" + (summary.isDefault ? "" : ".circle.fill"))
                Text(summary.shortText)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.Localizable.FiltersView.Title.filters)
        .accessibilityValue(summary.shortText)
    }
}

/// "Page 2" between the pages of a numbered list, across the columns, at a given height.
struct WallListPageDivider: View {
    let page: Int
    let height: CGFloat

    @Environment(\.look) private var look

    var body: some View {
        HStack(spacing: 10) {
            Text(L10n.Localizable.List.Page.divider(page))
                .font(.footnote.weight(.semibold))
                .foregroundStyle(look.secondaryLabel)
                .fixedSize()
            Rectangle()
                .fill(look.separator)
                .frame(height: 1)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 6)
        .frame(height: height)
        .accessibilityAddTraits(.isHeader)
    }
}

/// What follows the last cover: nothing while more may follow (it asks for the next page when
/// it appears; the placeholder tiles above it stand for a page on its way), "Couldn't load
/// more · Retry", and at the end a short rule.
struct WallListFooter: View {
    let footer: ListFeed.Footer
    let retry: () -> Void

    @Environment(\.look) private var look

    var body: some View {
        ZStack {
            switch footer {
            case .more, .loading:
                Color.clear
            case .failed:
                ListLoadMoreFailedRow(retry: retry)
            case .end:
                Capsule()
                    .fill(look.separator)
                    .frame(width: 36, height: 3)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 50)
    }
}
