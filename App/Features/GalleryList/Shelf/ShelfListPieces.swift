import EhFeatures
import EhModels
import SwiftUI

// What Shelf's list draws besides its rows (`shelf.md` section 3, "States" and "List
// controls"). Everything here scrolls with the rows, so nothing in it is glass.

/// Signed out, empty or failed: the shared state views, in place of the rows.
struct ShelfListState: View {
    let input: ListDesignInput

    var body: some View {
        switch input.feed.phase {
        case .signedOut(let kind):
            ListSignInState(kind: kind)
        case .empty:
            ListEmptyState(filters: filters)
        case .failed(let error):
            ListFailedState(error: error) { input.feed.retry() }
        case .loading, .content:
            EmptyView()
        }
    }

    /// "Filters" when the list's filter narrows something.
    private var filters: (() -> Void)? {
        guard let summary = input.controls.menu.filterSummary, !summary.isDefault else { return nil }
        let perform = input.perform
        return { perform(.filters) }
    }
}

/// A row while the first page loads: a cover block and three bars that shimmer.
struct ShelfListPlaceholderRow: View {
    static let count = 8

    let style: ShelfRowStyle

    var body: some View {
        let fill = style.texts.look.fill2
        HStack(alignment: .top, spacing: ShelfGalleryRow.coverSpacing) {
            RoundedRectangle(cornerRadius: ShelfGalleryRow.coverRadius, style: .continuous)
                .fill(fill)
                .frame(width: style.cover.width, height: style.cover.height)
                .padding(.leading, style.isRanked ? ShelfGalleryRow.rankWidth + ShelfGalleryRow.rankSpacing : 0)
            VStack(alignment: .leading, spacing: 10) {
                bar(fill, width: 220, height: 16)
                bar(fill, width: 120, height: 12)
                bar(fill, width: 160, height: ShelfRowMetrics.capsuleHeight)
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, minHeight: style.height, maxHeight: style.height, alignment: .topLeading)
        .shimmering()
        .accessibilityHidden(true)
    }

    private func bar(_ fill: Color, width: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(fill)
            .frame(maxWidth: width, minHeight: height, maxHeight: height)
    }
}

/// The row after the last gallery: nothing while more may follow (it asks for the next page
/// when it appears), a spinner while a page loads, "Couldn't load more · Retry", and at the end
/// a short rule.
struct ShelfListFooterRow: View {
    let footer: ListFeed.Footer
    let retry: () -> Void

    @Environment(\.look) private var look

    var body: some View {
        ZStack {
            switch footer {
            case .more:
                Color.clear
            case .loading:
                ProgressView()
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

/// "Page 2" between Toplists' pages.
struct ShelfListPageDivider: View {
    let page: Int

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
        .accessibilityAddTraits(.isHeader)
    }
}

/// The list's primary control where the bar does not hold it: the filter summary as a pill
/// ("8 of 10 · ★ 3+") that opens Filters, or in a favourites folder the line "Sorted by date
/// favorited" with "Sort", a menu of the orders the site has.
struct ShelfListHeaderLine: View {
    let control: ListPrimaryControl
    let perform: (ListMenuAction) -> Void

    @Environment(\.look) private var look

    var body: some View {
        switch control {
        case .filter(let summary):
            ShelfListFilterPill(summary: summary) { perform(.filters) }
                .frame(maxWidth: .infinity, alignment: .leading)
        case .sort(let picker):
            HStack {
                Text(Self.sortedBy(picker))
                    .font(.footnote)
                    .foregroundStyle(look.secondaryLabel)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Menu {
                    ForEach(picker.options) { option in
                        Toggle(isOn: Binding(
                            get: { option.id == picker.selection }, set: { _ in perform(.sort(option.id)) }
                        )) {
                            Text(option.title)
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.arrow.down")
                        Text(L10n.Localizable.List.sort)
                    }
                    .font(.subheadline.weight(.medium))
                }
                .menuStyle(.button)
                .buttonStyle(.borderless)
            }
        }
    }

    /// The order a favourites list is in. The options are `FavoritesSortOrder`'s cases by raw
    /// value (`FolderListHost`); nothing is said before the site has told the order.
    private static func sortedBy(_ picker: ListMenuPicker) -> String {
        switch picker.selection.flatMap(EhSetting.FavoritesSortOrder.init(rawValue:)) {
        case .favoritedTime: L10n.Localizable.List.Sorted.favorited
        case .lastUpdateTime: L10n.Localizable.List.Sorted.posted
        case nil: ""
        }
    }
}

/// "8 of 10 · ★ 3+" in the tint on `fill3`, 32 high, with the filter symbol; filled while the
/// filter is not the default.
struct ShelfListFilterPill: View {
    let summary: FilterSummary
    let action: () -> Void

    @Environment(\.look) private var look

    var body: some View {
        Button(action: action) {
            Label {
                Text(summary.shortText)
            } icon: {
                Image(systemName: summary.isDefault ? "line.3.horizontal.decrease" : "line.3.horizontal.decrease.circle.fill")
            }
            .font(.footnote.weight(.semibold))
            .lineLimit(1)
            .padding(.leading, 10)
            .padding(.trailing, 12)
            .frame(minHeight: 32)
            .background(look.fill3, in: .capsule)
            .foregroundStyle(.tint)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.Localizable.FiltersView.Title.filters)
        .accessibilityValue(summary.shortText)
    }
}
