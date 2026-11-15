import EhCore
import EhFeatures
import EhModels
import SwiftUI

/// While typing: the tags for the word at the caret, in reverse, so the best match is the row
/// nearest the field, on a fill (`wall.md` section 6). Choosing a tag turns the word into its
/// token. Return submits the text as typed.
///
/// Tag rows come only with the tags extension, its suggestion setting and a dictionary, as
/// before; without them only the quick searches and the Filters row stand above the field.
struct WallSearchSuggestions: View {
    let model: SearchSurfaceModel

    @Environment(\.searchFieldController) private var field

    var body: some View {
        let rows = TagSuggestionRowContent.rows(for: model.suggestions.suggestions)
        // The model ranks the best first; the rows are drawn from the field upward.
        let bottomUp = Array(rows.enumerated().reversed())
        ForEach(bottomUp, id: \.element.id) { ranked in
            Button { field.accept(ranked.element.item) } label: {
                WallTagSuggestionRow(row: ranked.element)
            }
            .buttonStyle(WallSearchRowStyle(isHighlighted: ranked.offset == 0))
            // VoiceOver reads the best match first, as it is nearest the field.
            .accessibilitySortPriority(Double(rows.count - ranked.offset))
        }
    }
}

/// A tag: the namespace in its colour right-aligned in the leading column, the tag with the
/// typed part bold, and its translated name trailing. One element for VoiceOver.
private struct WallTagSuggestionRow: View {
    let row: TagSuggestionRowContent

    @Environment(\.look) private var look

    var body: some View {
        WallSearchColumns {
            Text(verbatim: row.namespace.rawValue)
                .font(.caption.weight(.semibold))
                .foregroundStyle(row.namespace.markColor)
        } main: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(row.tag)
                    .foregroundStyle(look.label)
                    .layoutPriority(1)
                Spacer(minLength: 0)
                // The dictionary has no name for the tag: the row would say it twice.
                if !row.translation.characters.elementsEqual(row.tag.characters) {
                    Text(row.translation)
                        .font(.subheadline)
                        .foregroundStyle(look.secondaryLabel)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.accessibilityLabel)
    }
}

/// "Filters · 8 of 10 · ★ 3+" at the top of the suggestions, or of the recent searches before
/// typing: the drawing has no filter control, and the filter must stay reachable while
/// searching. It opens Filters on the scope's set; Favourites have none, so it is absent there.
struct WallSearchFiltersRow: View {
    let model: SearchSurfaceModel

    var body: some View {
        if let range = model.scope.filterRange {
            WallSearchFiltersButton(range: range, open: model.root.showFilters)
        }
    }
}

private struct WallSearchFiltersButton: View {
    let range: FilterRange
    let open: () -> Void

    @Environment(FilterStore.self) private var filterStore
    @Environment(\.look) private var look

    var body: some View {
        let summary = FilterSummary(filterStore[range])
        let text = summary.shortText
        Button(action: open) {
            WallSearchColumns {
                Image(systemName: summary.isDefault ? "line.3.horizontal.decrease" : "line.3.horizontal.decrease.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(look.secondaryLabel)
            } main: {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(L10n.Localizable.ToolbarItem.Button.filters)
                        .foregroundStyle(look.label)
                        .layoutPriority(1)
                    Spacer(minLength: 0)
                    Text(text)
                        .font(.subheadline)
                        .foregroundStyle(look.secondaryLabel)
                }
            }
        }
        .buttonStyle(WallSearchRowStyle())
        .accessibilityLabel(L10n.Localizable.ToolbarItem.Button.filters)
        .accessibilityValue(text)
    }
}
