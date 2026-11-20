import SwiftUI

/// The Library tab's root: a Favourites / History switch that the bar owns, over the library
/// part and the History list (`Design/designs/README.md` section 5.1, `shelf.md` section 7).
/// History is not part of the library design: it is a list.
///
/// The bar supplies the title, the account button (`tabsAccountButton()`, added around this
/// view) and the switch, pinned under the top bar. A title set by the screen under the switch
/// would win over this one, so History is asked for without its own; the library part leaves
/// its title out under `tabs`, or gives its list the tab's.
///
/// One screen exists at a time: two screens kept alive under one navigation bar both put
/// their items into it. So only what is owned above the switch outlives it. The segment
/// does, in `TabsBarLibrarySwitch`. What each screen loaded does not: the favourites' model is
/// `LibraryScreen`'s own and History's is its list's, so each loads again when its segment
/// is chosen again.
struct TabsBarLibraryTab: View {
    let library: TabsBarLibrarySwitch

    var body: some View {
        Group {
            switch library.segment {
            case .favorites: LibraryScreen(model: library.favorites)
            case .history: GalleryListScreen(context: .place(.history, heading: .screen))
            }
        }
        .navigationTitle(L10n.Localizable.Shell.Tab.library)
        // Large and leading, as part of the bar: a large title that scrolls with the content
        // would start under the switch, which is pinned below the bar.
        .toolbarTitleDisplayMode(.inlineLarge)
        .topBar {
            TabsBarLibraryPicker(library: library)
        }
    }
}

/// The switch itself: the system's segmented control (`README.md` section 13).
private struct TabsBarLibraryPicker: View {
    @Bindable var library: TabsBarLibrarySwitch

    private static var maximumWidth: CGFloat { 420 }

    var body: some View {
        Picker(L10n.Localizable.Shell.Tab.library, selection: $library.segment) {
            Text(L10n.Localizable.Shell.Library.favorites).tag(TabsBarLibrarySegment.favorites)
            Text(L10n.Localizable.HistoryView.Title.history).tag(TabsBarLibrarySegment.history)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        // Two segments across an iPad's window would be a control a foot wide.
        .frame(maxWidth: Self.maximumWidth)
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
    }
}
