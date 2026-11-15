import Foundation

// What the controls show of the page states: the failed-page count and whether the current
// page has its image.
//
// The page states stay out of observation (a page that resolves touches that page's view and
// nothing in SwiftUI); these two summaries are observable instead. Each is worked out again
// after whatever can change it and written only when it changed, so pages resolving one after
// another touch SwiftUI only when the current page gets its image.
extension ReaderModel {
    /// Counts the failed pages again: those that could not be resolved and those whose image
    /// did not load, a page that failed both ways once. A pass over the pages the resolver
    /// knows, a few microseconds for a long gallery, after a failure, a recovery or a command.
    func refreshFailedPageCount() {
        var count = failedImagePages.count
        for (page, status) in resolver.statuses where !failedImagePages.contains(page) {
            if case .failed = status {
                count += 1
            }
        }
        if count != failedPageCount {
            failedPageCount = count
        }
    }

    func refreshCurrentPageHasImage() {
        let hasImage = resolver.image(of: currentPage) != nil
        if hasImage != currentPageHasImage {
            currentPageHasImage = hasImage
        }
    }

    /// A page's state changed: only the current page's matters to the image summary.
    func pageDidChange(_ page: Int) {
        if page == currentPage {
            refreshCurrentPageHasImage()
        }
    }

    /// Both summaries again, after a command that changed many pages at once.
    func refreshPageSummary() {
        refreshFailedPageCount()
        refreshCurrentPageHasImage()
    }
}
