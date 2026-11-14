import EhModels

/// Whether the reader can translate the gallery's pages. Translation is not built yet, so the
/// controls each design reserves for it are not in the hierarchy.
nonisolated public enum ReaderTranslationAvailability: Hashable, Sendable {
    case unavailable
}

// The closing page after the last page (`Design/designs/closing-page.md`) and translation.
extension ReaderModel {
    /// Always `.unavailable` in this build.
    public var translationAvailability: ReaderTranslationAvailability { .unavailable }

    /// The engine's report that the closing page became current, or stopped being current.
    /// Auto-play stops on it: the advance onto the closing page is its last.
    public func trailerVisibilityDidChange(_ isCurrent: Bool) {
        if isAtEnd != isCurrent {
            isAtEnd = isCurrent
        }
        if isCurrent, autoPlay != .off {
            setAutoPlay(.off)
        }
    }
}
