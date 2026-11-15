import SwiftUI

// The library's title, drawn the way the Index draws its own (`ledger.md` sections 2 and 7):
// large in the look's title face at the top of the page, and in the bar once that has
// scrolled under it.

/// "Favourites", 36 pt bold in the look's title face.
struct LedgerLibraryTitle: View {
    @ScaledMetric(relativeTo: .largeTitle) private var size: CGFloat = 36
    @Environment(\.look) private var look

    var body: some View {
        Text(L10n.Localizable.Shell.Place.favorites)
            .font(.system(size: size, weight: .bold))
            .lookTitleDesign()
            .foregroundStyle(look.label)
            .lineLimit(1)
            .accessibilityAddTraits(.isHeader)
    }
}

extension View {
    /// The screen's name for Back and VoiceOver, and the bar's title in the look's title face:
    /// hidden while the page's own title is in view, unless `isAlwaysVisible` (a screen with
    /// no title of its own). Nothing when `isShown` is false: under `tabs` the Library tab
    /// names the screen.
    func ledgerLibraryBarTitle(isShown: Bool, isAlwaysVisible: Bool) -> some View {
        modifier(LedgerLibraryBarTitle(isShown: isShown, isAlwaysVisible: isAlwaysVisible))
    }
}

private struct LedgerLibraryBarTitle: ViewModifier {
    let isShown: Bool
    let isAlwaysVisible: Bool

    @State private var isPastTitle = false
    @Environment(\.look) private var look

    /// About the height of the page's title.
    private static let scrollDistance: CGFloat = 40

    func body(content: Content) -> some View {
        if isShown {
            content
                .onScrollGeometryChange(for: Bool.self) { geometry in
                    geometry.contentOffset.y + geometry.contentInsets.top > Self.scrollDistance
                } action: { _, isPast in
                    isPastTitle = isPast
                }
                .navigationTitle(L10n.Localizable.Shell.Place.favorites)
                .toolbarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        let isVisible = isAlwaysVisible || isPastTitle
                        Text(L10n.Localizable.Shell.Place.favorites)
                            .font(.headline)
                            .lookTitleDesign()
                            .foregroundStyle(look.label)
                            .opacity(isVisible ? 1 : 0)
                            .animation(.easeInOut(duration: 0.15), value: isVisible)
                            .accessibilityHidden(!isVisible)
                    }
                }
        } else {
            content
        }
    }
}
