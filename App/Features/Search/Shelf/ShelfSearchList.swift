import EhFeatures
import SwiftUI

/// What the surface shows above the field (`shelf.md` section 6): the quick searches; before
/// anything is typed, the recent searches and the recently seen galleries, or one line when
/// there is none of the three; while typing, the suggestions.
///
/// A plain list, so a recent search can be swiped away. Each group is a view of its own that
/// reads only its own list, so a page of suggestions redraws the suggestions and nothing
/// else; none of them reads the typed text. Everything here is content: no glass.
struct ShelfSearchList: View {
    let model: SearchSurfaceModel
    let isTyping: Bool

    var body: some View {
        List {
            ShelfQuickSearches(model: model)
            if isTyping {
                ShelfSearchSuggestions(model: model)
            } else {
                ShelfRecentSearches(model: model)
                ShelfRecentlySeen(model: model)
                ShelfSearchHint(root: model.root)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        // Headings are shorter than the system's 44 pt rows; each row sets its own height.
        .environment(\.defaultMinListRowHeight, 0)
    }
}

/// With no quick searches, no recent searches and nothing seen: one line saying what the
/// field takes.
private struct ShelfSearchHint: View {
    let root: SearchRootModel

    @Environment(\.look) private var look

    var body: some View {
        if root.quickSearchWords.isEmpty, root.historyKeywords.isEmpty, root.recentGalleries.isEmpty {
            Text(L10n.Localizable.Search.hint)
                .font(.subheadline)
                .foregroundStyle(look.secondaryLabel)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
                .shelfSearchRow()
        }
    }
}

/// A group's label: small capitals in the secondary colour, with a link in the tint
/// trailing ("Edit", "Clear"). The line is 44 pt high when it has a link, the link's target.
struct ShelfSearchHeading<Link: View>: View {
    let title: String
    @ViewBuilder var link: Link

    @Environment(\.look) private var look

    private var hasLink: Bool { Link.self != EmptyView.self }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .tracking(0.3)
                .textCase(.uppercase)
                .foregroundStyle(look.secondaryLabel)
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            link
                .font(.subheadline.weight(.medium))
                // In a list row only the link takes the tap, not the whole row.
                .buttonStyle(.borderless)
        }
        .frame(maxWidth: .infinity, minHeight: hasLink ? 44 : 30, alignment: .leading)
        .padding(.top, hasLink ? 6 : 14)
        .shelfSearchRow()
    }
}

extension ShelfSearchHeading where Link == EmptyView {
    init(title: String) {
        self.init(title: title) { EmptyView() }
    }
}

nonisolated enum ShelfSearchMetrics {
    /// Text rows start 20 pt from the leading edge and end 16 pt from the trailing one.
    static let rowInsets = EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 16)
    /// Where a shelf's first item starts.
    static let shelfMargin: CGFloat = 20
}

extension View {
    /// A row of Shelf's search list: on the look's ground, with a separator under it only when
    /// `separator` says so (between rows of one group, never under a group's last row).
    func shelfSearchRow(insets: EdgeInsets = ShelfSearchMetrics.rowInsets, separator: Bool = false) -> some View {
        listRowInsets(insets)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden, edges: .top)
            .listRowSeparator(separator ? .automatic : .hidden, edges: .bottom)
    }
}
