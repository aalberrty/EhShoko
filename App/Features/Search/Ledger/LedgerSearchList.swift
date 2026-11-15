import EhFeatures
import SwiftUI

/// What the surface shows above the field (`ledger.md` section 6): the title, the copied-link
/// card, the tag suggestions, and the groups that follow what is typed.
///
/// A plain list, so a recent search can be swiped away. Each group is a view of its own that
/// reads only what it shows: the tags read the suggestions, the card reads the link offer, and
/// one view reads the typed text for the groups it filters. Everything here is content: no
/// glass.
struct LedgerSearchList: View {
    let model: SearchSurfaceModel

    var body: some View {
        List {
            LedgerSearchTitle()
            LedgerCopiedLinkCard(model: model)
            LedgerTagSuggestions(model: model)
            LedgerSearchTypedGroups(model: model)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .ledgerSearchBarTitle()
    }
}

/// "Search", 30 pt bold in the look's title face, as the list's first row.
private struct LedgerSearchTitle: View {
    @ScaledMetric(relativeTo: .largeTitle) private var size: CGFloat = 30
    @Environment(\.look) private var look

    var body: some View {
        Text(L10n.Localizable.SearchView.Title.search)
            .font(.system(size: size, weight: .bold))
            .lookTitleDesign()
            .foregroundStyle(look.label)
            .lineLimit(1)
            .accessibilityAddTraits(.isHeader)
            .frame(maxWidth: .infinity, alignment: .leading)
            .ledgerSearchRow(insets: EdgeInsets(top: 0, leading: 20, bottom: 2, trailing: 20))
    }
}

extension View {
    /// The bar's own title stays empty while the list's title is in view, and shows the same
    /// word in the look's title face once that has scrolled under the bar (as the Index does).
    fileprivate func ledgerSearchBarTitle() -> some View {
        modifier(LedgerSearchBarTitle())
    }
}

private struct LedgerSearchBarTitle: ViewModifier {
    @State private var isShown = false
    @Environment(\.look) private var look

    /// About the height of the list's title.
    private static let scrollDistance: CGFloat = 36

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top > Self.scrollDistance
            } action: { _, isPast in
                isShown = isPast
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(L10n.Localizable.SearchView.Title.search)
                        .font(.headline)
                        .lookTitleDesign()
                        .foregroundStyle(look.label)
                        .opacity(isShown ? 1 : 0)
                        .animation(.easeInOut(duration: 0.15), value: isShown)
                        .accessibilityHidden(!isShown)
                }
            }
    }
}

// MARK: The copied link

/// "Open copied link" when the clipboard probably holds a link and the setting allows it.
/// The card does not show the link: reading it would bring up the paste prompt, so it is read
/// only when the card is tapped (`controller.openCopiedLink()`), and opened as a shared link
/// is.
private struct LedgerCopiedLinkCard: View {
    let model: SearchSurfaceModel

    @Environment(\.searchFieldController) private var field

    var body: some View {
        if model.hasLinkOffer {
            Button { field.openCopiedLink() } label: {
                LedgerCopiedLinkLabel()
            }
            .buttonStyle(.plain)
            .ledgerSearchRow(insets: EdgeInsets(top: 4, leading: 16, bottom: 6, trailing: 16))
        }
    }
}

/// A card 60 pt high on the look's raised colour with a hairline: the link symbol in the tint,
/// the title and what it is, and an "Open" pill in the tint. At accessibility sizes the pill
/// gives its room to the words; the whole card is the button.
private struct LedgerCopiedLinkLabel: View {
    @Environment(\.look) private var look
    @Environment(\.onTint) private var onTint
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        HStack(spacing: 12) {
            Image(systemName: "link")
                .font(.title3)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(L10n.Localizable.Search.Link.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(look.label)
                Text(L10n.Localizable.Search.Link.body)
                    .font(.caption)
                    .foregroundStyle(look.secondaryLabel)
            }
            .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
            Spacer(minLength: 0)
            if !typeSize.isAccessibilitySize {
                Text(L10n.Localizable.Search.Link.open)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(onTint)
                    .padding(.horizontal, 15)
                    .frame(minHeight: 34)
                    .background(.tint, in: .capsule)
                    .accessibilityHidden(true)
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
        .background(look.raised, in: shape)
        .overlay { shape.strokeBorder(look.separator, lineWidth: 0.5) }
        .contentShape(shape)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.Localizable.Search.Link.title)
        .accessibilityValue(L10n.Localizable.Search.Link.body)
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: Headings and rows

/// A group's heading in Ledger's small capitals, with a link in the tint trailing ("Clear").
/// At accessibility sizes the link goes under the heading, so neither is cut short.
struct LedgerSearchHeading<Link: View>: View {
    let title: String
    @ViewBuilder var link: Link

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) {
                    label
                    styledLink
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    label
                    Spacer(minLength: 0)
                    styledLink
                }
            }
        }
        // The list's 44 pt row, with the words at its foot, next to the group they head.
        .padding(.bottom, 3)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .bottomLeading)
        .ledgerSearchRow()
    }

    private var label: some View {
        Text(title)
            .ledgerSmallCaps()
            .lineLimit(typeSize.isAccessibilitySize ? 2 : 1)
            .accessibilityAddTraits(.isHeader)
    }

    private var styledLink: some View {
        link
            .font(.subheadline.weight(.medium))
            // In a list row only the link takes the tap, not the whole row.
            .buttonStyle(.borderless)
    }
}

extension LedgerSearchHeading where Link == EmptyView {
    init(title: String) {
        self.init(title: title) { EmptyView() }
    }
}

/// Where a row of the list has a separator. A plain list hides the line between two rows when
/// either of them hides its edge, so a row in a group sets only its bottom edge and leaves the
/// line above it to the row before.
nonisolated enum LedgerSearchSeparator {
    /// The title, the card, a heading or the hint: no line above or below.
    case none
    /// A row with another row of its group below it.
    case below
    /// The last row of a group: the line above it, none below.
    case last

    static func row(isLast: Bool) -> Self { isLast ? .last : .below }
}

nonisolated enum LedgerSearchMetrics {
    /// Rows run from 20 pt to 20 pt, as drawn.
    static let rowInsets = EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20)
}

extension View {
    /// A row of Ledger's search list: on the look's ground, with hairlines in the look's
    /// separator colour only between the rows of one group.
    func ledgerSearchRow(
        insets: EdgeInsets = LedgerSearchMetrics.rowInsets, separator: LedgerSearchSeparator = .none
    ) -> some View {
        modifier(LedgerSearchRow(insets: insets, separator: separator))
    }
}

private struct LedgerSearchRow: ViewModifier {
    let insets: EdgeInsets
    let separator: LedgerSearchSeparator

    @Environment(\.look) private var look

    func body(content: Content) -> some View {
        content
            .listRowInsets(insets)
            .listRowBackground(Color.clear)
            .listRowSeparatorTint(look.separator)
            .listRowSeparator(separator == .none ? .hidden : .automatic, edges: .top)
            .listRowSeparator(separator == .below ? .automatic : .hidden, edges: .bottom)
    }
}
