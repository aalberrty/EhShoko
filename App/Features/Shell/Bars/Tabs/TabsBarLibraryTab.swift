import SwiftUI

/// The Library tab's root: a Favourites / History switch that the bar owns, over the library
/// part and the History list (`Design/designs/README.md` section 5.1). History is not part
/// of the library design: it is a list.
///
/// A first working form, for task A1: the switch is the system's segmented control in the
/// top bar, and the two screens do not keep their state across it.
struct TabsBarLibraryTab: View {
    @State private var segment = TabsBarLibrarySegment.favorites

    var body: some View {
        Group {
            switch segment {
            case .favorites: LibraryScreen()
            case .history: GalleryListScreen(context: .place(.history))
            }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker(L10n.Localizable.Shell.Tab.library, selection: $segment) {
                    Text(L10n.Localizable.Shell.Library.favorites).tag(TabsBarLibrarySegment.favorites)
                    Text(L10n.Localizable.HistoryView.Title.history).tag(TabsBarLibrarySegment.history)
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }
        }
    }
}

nonisolated enum TabsBarLibrarySegment: Hashable, Sendable {
    case favorites
    case history
}
