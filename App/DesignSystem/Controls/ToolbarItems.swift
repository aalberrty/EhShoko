import SwiftUI

// Legacy `CustomToolbarItem` wrapped several buttons in one `HStack` item. On iOS 26 that defeats
// the toolbar's own glass grouping, so it is not ported: use `ToolbarItemGroup` (and
// `ToolbarSpacer` to split groups, iOS 26 only), with `.tint` / `.disabled` on the items themselves.

/// The "more" menu at the trailing edge of a toolbar (legacy `ToolbarFeaturesMenu`).
struct ToolbarFeaturesMenu<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        Menu {
            content
        } label: {
            // The symbol carries the system's localized "More" label for VoiceOver.
            Image(systemName: "ellipsis")
        }
    }
}

/// Opens the search filters (legacy `FiltersButton`). Inside a menu it shows its title too.
struct FiltersButton: View {
    private let action: () -> Void

    init(action: @escaping () -> Void) {
        self.action = action
    }

    var body: some View {
        Button(L10n.Localizable.ToolbarItem.Button.filters, systemImage: "line.3.horizontal.decrease", action: action)
    }
}

private struct ToolbarItemsPreview: View {
    var body: some View {
        NavigationStack {
            List {
                Text(verbatim: "Toolbar")
            }
            .navigationTitle(L10n.Localizable.TabItem.Title.favorites)
            .toolbar {
                ToolbarItem {
                    ToolbarFeaturesMenu {
                        FiltersButton {}
                    }
                }
            }
        }
    }
}

#Preview {
    ToolbarItemsPreview()
}

#Preview("Dark") {
    ToolbarItemsPreview().preferredColorScheme(.dark)
}
