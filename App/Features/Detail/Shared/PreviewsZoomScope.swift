import SwiftUI

extension View {
    /// Gives a pushed screen of all previews a zoom namespace of its own, for the reader it
    /// opens from a thumbnail. Its thumbnails are marked `.preview(gid:page:)`, as are those
    /// of the gallery page's strip, which stays below it in the stack; in the app's one
    /// namespace two sources would share an id (`spikes/S4.md`, rule 3). The screen opens
    /// the reader from nothing else, so nothing it needs is in the app's namespace.
    ///
    /// Apply it outside the screen's `readerCover`, which reads the namespace where it is.
    func previewsZoomScope() -> some View {
        modifier(PreviewsZoomScope())
    }
}

private struct PreviewsZoomScope: ViewModifier {
    @Namespace private var namespace

    func body(content: Content) -> some View {
        content.environment(\.zoomNamespace, namespace)
    }
}
