import EhFeatures
import SwiftUI

/// What Wall's surface shows above the field, anchored to the bottom (`wall.md` section 6):
/// short content sits on the field, long content starts scrolled to it, and a change of
/// height keeps the rows nearest the field in place.
///
/// Top to bottom: before typing, the recently seen covers; the quick searches; the Filters
/// row; then the recent searches before typing and the suggestions while typing, each in
/// reverse so the first is nearest the field. Each group is a view of its own that reads only
/// its own list; none of them reads the typed text. Everything here is content: no glass.
struct WallSearchStack: View {
    let model: SearchSurfaceModel
    let isTyping: Bool

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if !isTyping {
                    WallRecentlySeen(model: model)
                }
                WallQuickSearches(model: model)
                WallSearchFiltersRow(model: model)
                if isTyping {
                    WallSearchSuggestions(model: model)
                } else {
                    WallRecentSearches(model: model)
                }
            }
        }
        .scrollIndicators(.hidden)
        .defaultScrollAnchor(.bottom, for: .alignment)
        .defaultScrollAnchor(.bottom, for: .initialOffset)
        .defaultScrollAnchor(.bottom, for: .sizeChanges)
    }
}

nonisolated enum WallSearchMetrics {
    /// Rows start 20 pt from the edges, as their lines do.
    static let rowInset: CGFloat = 20
    /// The highlighted row's fill stands 8 pt in from the edges.
    static let highlightInset: CGFloat = 8
    static let highlightRadius: CGFloat = 16
    static let rowHeight: CGFloat = 48
    /// The leading column of a row: the namespace, or a symbol. Scaled with the caption.
    static let leadWidth: CGFloat = 70
    static let columnSpacing: CGFloat = 12
}

/// A group's label in the look's heading style, with a link trailing ("Edit", "Clear"). The
/// line is 44 pt high when it has a link, the link's target. At accessibility sizes the link
/// goes under the label, so neither is cut short.
struct WallSearchHeading<Trailing: View>: View {
    let title: String
    @ViewBuilder var link: Trailing

    @Environment(\.dynamicTypeSize) private var typeSize

    private var hasLink: Bool { Trailing.self != EmptyView.self }

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
        .frame(maxWidth: .infinity, minHeight: hasLink ? 44 : 30, alignment: .bottomLeading)
        .padding(.horizontal, WallSearchMetrics.rowInset)
        .padding(.top, hasLink ? 6 : 14)
        .padding(.bottom, hasLink ? 0 : 8)
    }

    private var label: some View {
        Text(title)
            .lookSectionHeader()
            .lineLimit(typeSize.isAccessibilitySize ? 2 : 1)
    }

    private var styledLink: some View {
        link
            .font(.footnote.weight(.semibold))
            .buttonStyle(.borderless)
    }
}

extension WallSearchHeading where Trailing == EmptyView {
    init(title: String) {
        self.init(title: title) { EmptyView() }
    }
}

/// A row's two columns: the leading column, its content trailing (a namespace or a symbol),
/// and the rest. At accessibility sizes the column goes above the rest, so the words keep the
/// row's width and wrap rather than lose their middle.
struct WallSearchColumns<Lead: View, Main: View>: View {
    @ViewBuilder var lead: Lead
    @ViewBuilder var main: Main

    @ScaledMetric(relativeTo: .caption) private var leadWidth = WallSearchMetrics.leadWidth
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 2) {
                    lead
                    main
                }
                .padding(.vertical, 6)
            } else {
                HStack(spacing: WallSearchMetrics.columnSpacing) {
                    lead.frame(width: leadWidth, alignment: .trailing)
                    main
                }
            }
        }
        .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
    }
}

/// A row of the surface as a button: 48 pt high, a line above it 20 pt in from both edges, and
/// the fill of the highlighted row (corner 16, 8 pt in) when it is the best match or pressed.
/// The highlighted row has no line: its fill separates it.
struct WallSearchRowStyle: ButtonStyle {
    var isHighlighted = false

    func makeBody(configuration: Configuration) -> some View {
        WallSearchRowBody(label: configuration.label, isHighlighted: isHighlighted, isPressed: configuration.isPressed)
    }
}

private struct WallSearchRowBody<Content: View>: View {
    let label: Content
    let isHighlighted: Bool
    let isPressed: Bool

    @Environment(\.look) private var look
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        label
            .padding(.horizontal, WallSearchMetrics.rowInset - WallSearchMetrics.highlightInset)
            .frame(maxWidth: .infinity, minHeight: WallSearchMetrics.rowHeight, alignment: .leading)
            .contentShape(.rect)
            .background {
                if isHighlighted || isPressed {
                    RoundedRectangle(cornerRadius: WallSearchMetrics.highlightRadius, style: .continuous)
                        .fill(isPressed ? look.fill2 : look.fill3)
                }
            }
            .padding(.horizontal, WallSearchMetrics.highlightInset)
            .overlay(alignment: .top) {
                if !isHighlighted {
                    Rectangle()
                        .fill(look.separator)
                        .frame(height: 1 / displayScale)
                        .padding(.horizontal, WallSearchMetrics.rowInset)
                }
            }
    }
}
