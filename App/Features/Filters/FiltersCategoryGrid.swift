import EhFeatures
import EhModels
import SwiftUI

/// The ten categories as tiles in two columns, under "8 of 10 categories". A tile on a 22% tint
/// of its hue with a filled mark is shown in results; a struck-through tile on the look's fill
/// is excluded.
struct FiltersCategorySection: View {
    let model: FiltersModel

    var body: some View {
        Section {
            FiltersCategoryGrid(model: model)
        } header: {
            // Counted as the site receives the filter, like the lists' summaries: excluding
            // every category is no category filter.
            Text(
                L10n.Localizable.List.Filter.Summary.categories(
                    FilterSummary(model.filter).categoriesShown, FilterSummary.categoryCount
                )
            )
            .filtersSectionHeader()
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets())
    }
}

private struct FiltersCategoryGrid: View {
    let model: FiltersModel

    @State private var toggles = 0

    /// The site's order, two to a row. A `Grid`, not a lazy one: ten tiles inside a list row.
    private static let rows: [[EhModels.Category]] = stride(from: 0, to: FiltersModel.categories.count, by: 2)
        .map { Array(FiltersModel.categories[$0..<min($0 + 2, FiltersModel.categories.count)]) }

    var body: some View {
        Grid(horizontalSpacing: 8, verticalSpacing: 8) {
            ForEach(Self.rows.indices, id: \.self) { index in
                GridRow {
                    ForEach(Self.rows[index]) { category in
                        FiltersCategoryTile(category: category, isExcluded: model.isExcluded(category)) {
                            toggles += 1
                            model.toggleExclusion(of: category)
                        }
                    }
                }
            }
        }
        .sensoryFeedback(.impact(flexibility: .soft), trigger: toggles)
    }
}

private struct FiltersCategoryTile: View {
    let category: EhModels.Category
    let isExcluded: Bool
    let toggle: () -> Void

    @Environment(\.look) private var look
    @ScaledMetric(relativeTo: .subheadline) private var height: CGFloat = 40
    @ScaledMetric(relativeTo: .subheadline) private var markSize: CGFloat = 18

    private static let shape = RoundedRectangle(cornerRadius: 13, style: .continuous)

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 9) {
                mark
                Text(category.localizedName)
                    .font(.subheadline.weight(.semibold))
                    .strikethrough(isExcluded, color: look.tertiaryLabel)
                    .foregroundStyle(isExcluded ? look.tertiaryLabel : look.label)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: height)
            .background(isExcluded ? look.fill3 : category.markColor.opacity(0.22), in: Self.shape)
            .contentShape(Self.shape)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isExcluded ? [] : .isSelected)
    }

    /// A check in the ground's colour on the hue, which reads on the dark hue of the light
    /// appearance and on the light hue of the dark one; an empty ring when excluded.
    @ViewBuilder private var mark: some View {
        if isExcluded {
            Circle()
                .strokeBorder(look.tertiaryLabel, lineWidth: 1.5)
                .frame(width: markSize, height: markSize)
                .accessibilityHidden(true)
        } else {
            Circle()
                .fill(category.markColor)
                .frame(width: markSize, height: markSize)
                .overlay {
                    Image(systemName: "checkmark")
                        .font(.system(size: markSize * 0.5, weight: .bold))
                        .foregroundStyle(look.background)
                }
                .accessibilityHidden(true)
        }
    }
}
