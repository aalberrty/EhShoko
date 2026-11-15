import EhFeatures
import SwiftUI

/// While typing: "Suggestions", then "Search titles for “gla”", which submits the text as
/// typed, then the tags for the word at the caret (`shelf.md` section 6). Choosing a tag turns
/// the word into its token.
///
/// Tag rows come only with the tags extension, its suggestion setting and a dictionary, as
/// before; without them the titles row stands alone.
struct ShelfSearchSuggestions: View {
    let model: SearchSurfaceModel

    @Environment(\.searchFieldController) private var field

    var body: some View {
        let rows = TagSuggestionRowContent.rows(for: model.suggestions.suggestions)
        ShelfSearchHeading(title: L10n.Localizable.Search.suggestions)
        SearchTitlesButton(model: model)
            .labelStyle(ShelfSearchTitlesLabelStyle())
            .shelfSearchRow(separator: .row(isLast: rows.isEmpty))
        ForEach(rows) { row in
            Button { field.accept(row.item) } label: {
                ShelfTagSuggestionRow(row: row)
            }
            .shelfSearchRow(separator: .row(isLast: row.id == rows.last?.id))
        }
    }
}

/// A tag: the namespace in its colour in the leading column, the tag with the typed part
/// bold, and its translated name trailing. One element for VoiceOver.
private struct ShelfTagSuggestionRow: View {
    let row: TagSuggestionRowContent

    @Environment(\.look) private var look

    var body: some View {
        ShelfSuggestionColumns {
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

/// The titles row in the tag rows' columns: its symbol where they have the namespace, its
/// words where they have the tag, in the label colour rather than the list's tint.
private struct ShelfSearchTitlesLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        ShelfSearchTitlesLabel(icon: configuration.icon, title: configuration.title)
    }
}

private struct ShelfSearchTitlesLabel<Icon: View, Title: View>: View {
    let icon: Icon
    let title: Title

    @Environment(\.look) private var look

    var body: some View {
        ShelfSuggestionColumns {
            icon.foregroundStyle(look.secondaryLabel)
        } main: {
            title.foregroundStyle(look.label)
        }
    }
}

/// A suggestion row's two columns: a leading column 72 pt wide at the default size, its
/// content trailing (a namespace or a symbol), and the rest. At accessibility sizes the
/// column goes above the rest, so the words keep the row's width. The separator starts where
/// the rest does.
private struct ShelfSuggestionColumns<Lead: View, Main: View>: View {
    @ViewBuilder var lead: Lead
    @ViewBuilder var main: Main

    @ScaledMetric(relativeTo: .caption) private var leadWidth: CGFloat = 72
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 2) {
                    lead
                    main.alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
                }
                .padding(.vertical, 6)
            } else {
                HStack(spacing: 12) {
                    lead.frame(width: leadWidth, alignment: .trailing)
                    main.alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
                }
            }
        }
        .lineLimit(1)
        .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
        .contentShape(.rect)
    }
}
