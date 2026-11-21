import EhModels

// The closing page after the last page (`Design/designs/closing-page.md`).
extension ReaderModel {
    /// The engine's report that the closing page became current, or stopped being current.
    /// Auto-play stops on it: the advance onto the closing page is its last.
    public func trailerVisibilityDidChange(_ isCurrent: Bool) {
        if isAtEnd != isCurrent {
            isAtEnd = isCurrent
            translation.atEndDidChange()
        }
        if isCurrent, autoPlay != .off {
            setAutoPlay(.off)
        }
    }
}
