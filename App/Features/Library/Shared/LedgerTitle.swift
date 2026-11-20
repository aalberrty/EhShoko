import SwiftUI

// The title of Ledger's Index and of Ledger's library (`ledger.md` sections 2 and 7): large in
// the look's title face at the top of the page, and in the bar once that has scrolled under it.

/// A Ledger screen's own title: 36 pt bold in the look's title face, 28 when compact (the
/// Index's iPad column).
struct LedgerTitle: View {
    let title: String
    var isCompact = false

    @ScaledMetric(relativeTo: .largeTitle) private var pageSize: CGFloat = 36
    @Environment(\.look) private var look

    init(_ title: String, isCompact: Bool = false) {
        self.title = title
        self.isCompact = isCompact
    }

    var body: some View {
        Text(title)
            .font(isCompact ? .title.bold() : .system(size: pageSize, weight: .bold))
            .lookTitleDesign()
            .foregroundStyle(look.label)
            .lineLimit(1)
            .accessibilityAddTraits(.isHeader)
    }
}

extension View {
    /// `title` as the screen's name for Back and VoiceOver, and as the bar's title in the
    /// look's title face: hidden while the page's own `LedgerTitle` is in view, shown once it
    /// has scrolled under the bar, or always when `isAlwaysVisible` (a screen with no title of
    /// its own). Nothing when `title` is `nil`: under `tabs` the Library tab names the screen.
    func ledgerBarTitle(_ title: String?, isAlwaysVisible: Bool = false) -> some View {
        modifier(LedgerBarTitle(title: title, isAlwaysVisible: isAlwaysVisible))
    }
}

private struct LedgerBarTitle: ViewModifier {
    let title: String?
    let isAlwaysVisible: Bool

    @State private var isPastTitle = false
    @Environment(\.look) private var look

    /// About the height of the page's title.
    private static let scrollDistance: CGFloat = 40

    func body(content: Content) -> some View {
        if let title {
            content
                .onScrollGeometryChange(for: Bool.self) { geometry in
                    geometry.contentOffset.y + geometry.contentInsets.top > Self.scrollDistance
                } action: { _, isPast in
                    isPastTitle = isPast
                }
                .navigationTitle(title)
                .toolbarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        let isVisible = isAlwaysVisible || isPastTitle
                        Text(title)
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
