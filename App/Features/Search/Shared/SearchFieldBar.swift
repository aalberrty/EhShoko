import EhFeatures
import SwiftUI

extension View {
    /// Places the search field bar as the surface's own bottom bar (`spikes/S6.md` section 6):
    /// on the keyboard, or on the keys row above it, while the field has focus; above the tab
    /// bar under `tabs` and at the bottom edge under `command` while it has not. The content
    /// scrolls under it and puts the keyboard away when dragged.
    ///
    /// `content` is the bar's row: the capsule with the field and one or two circles.
    func searchFieldBar(@ViewBuilder _ content: () -> some View) -> some View {
        scrollDismissesKeyboard(.interactively)
            .bottomBar(spacing: 0) { SearchFieldBar(content: content()) }
    }
}

/// The field bar's row: one glass container, so the capsule and its circles blend as the
/// system's controls do, 12 pt from the sides and 8 pt above the keyboard.
private struct SearchFieldBar<Content: View>: View {
    let content: Content

    var body: some View {
        GlassGroup(spacing: 8) {
            HStack(spacing: 8) { content }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

/// The bar's controls are 52 pt high, growing with Dynamic Type to 64 pt and no further, so
/// at the largest sizes the field keeps most of the width (`spikes/S6.md` section 8).
private enum SearchFieldControl {
    static let height: CGFloat = 52
    static func size(scaled: CGFloat) -> CGFloat { min(scaled, 64) }
}

/// The glass capsule that holds the field, with the scope menu or a magnifier before it.
struct SearchFieldCapsule<Leading: View, Field: View>: View {
    private let leading: Leading
    private let field: Field
    @ScaledMetric(relativeTo: .body) private var height = SearchFieldControl.height

    init(@ViewBuilder leading: () -> Leading, @ViewBuilder field: () -> Field) {
        self.leading = leading()
        self.field = field()
    }

    var body: some View {
        HStack(spacing: 6) {
            leading
                // The symbols stop growing before the field does.
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
            field
        }
        .padding(.leading, 16)
        .padding(.trailing, 10)
        .frame(maxWidth: .infinity, minHeight: SearchFieldControl.size(scaled: height))
        // Interactive: on iOS 26 the glass answers the touch while the field under it still
        // takes the tap and places the caret.
        .glassSurface(in: .capsule, isInteractive: true)
    }
}

/// The capsule's leading symbol where the scope is chosen elsewhere (Shelf's segmented
/// control).
struct SearchFieldMagnifier: View {
    @Environment(\.look) private var look

    var body: some View {
        Image(systemName: "magnifyingglass")
            .foregroundStyle(look.secondaryLabel)
            .accessibilityHidden(true)
    }
}

/// A round glass button beside the capsule: Filters, Close, Clear.
struct SearchFieldCircleButton: View {
    let systemImage: String
    let title: String
    var showsDot = false
    let action: () -> Void

    @ScaledMetric(relativeTo: .body) private var height = SearchFieldControl.height
    @Environment(\.look) private var look

    var body: some View {
        let size = SearchFieldControl.size(scaled: height)
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(look.label)
                .frame(width: size, height: size)
                .overlay(alignment: .topTrailing) {
                    if showsDot {
                        Circle()
                            .fill(.orange)
                            .frame(width: 9, height: 9)
                            .padding(size * 0.2)
                    }
                }
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .glassSurface(in: .circle, isInteractive: true)
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .accessibilityLabel(title)
        .accessibilityShowsLargeContentViewer {
            Label(title, systemImage: systemImage)
        }
    }
}

/// The Filters circle (Shelf leading, Ledger trailing): opens Filters on the scope's set.
/// Favourites have no filters, so it is dimmed there.
struct SearchFiltersButton: View {
    let model: SearchSurfaceModel

    var body: some View {
        SearchFieldCircleButton(
            systemImage: "line.3.horizontal.decrease", title: L10n.Localizable.ToolbarItem.Button.filters
        ) {
            model.root.showFilters()
        }
        .disabled(model.scope.filterRange == nil)
    }
}
