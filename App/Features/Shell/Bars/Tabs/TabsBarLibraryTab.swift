import SwiftUI

/// The Library tab's root: a Favourites / History switch that the bar owns, over the library
/// part and the History list (`Design/designs/README.md` section 5.1, `shelf.md` section 7).
/// History is not part of the library design: it is a list.
///
/// The bar supplies the title, the account button (`tabsAccountButton()`, added around this
/// view) and the switch, pinned under the top bar. A title set by the screen under the switch
/// would win over this one, so History is asked for without its own; the library part leaves
/// its title out under `tabs`.
///
/// One screen exists at a time. Two screens kept alive under one navigation bar both put
/// their items into it, so what must outlive the switch belongs above it: the segment is in
/// `TabsBarLibrarySwitch`; the favourites that were loaded are `LibraryScreen`'s.
struct TabsBarLibraryTab: View {
    /// The switch `TabsShell` owns.
    let library: TabsBarLibrarySwitch

    var body: some View {
        Group {
            switch library.segment {
            case .favorites: LibraryScreen()
            case .history: GalleryListScreen(context: .place(.history, embedsInStart: true))
            }
        }
        .navigationTitle(L10n.Localizable.Shell.Tab.library)
        // Large and leading, in the bar's own row: a large title below the bar would sit under
        // the switch's scroll edge effect on iOS 26 and be blurred by it.
        .toolbarTitleDisplayMode(.inlineLarge)
        .topBar {
            TabsBarLibraryPicker(library: library)
        }
    }
}

/// The switch itself: the system's segmented control (`README.md` section 13). It alone
/// writes the segment.
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
