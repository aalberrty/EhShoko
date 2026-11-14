import EhModels

/// How far the user has read a gallery: what the gallery page's Read button says ("Read",
/// "Continue · page 23 of 48", "Read again").
nonisolated public enum GalleryReadingStatus: Hashable, Sendable {
    case unread
    /// `page` is the 1-based page last read.
    case inProgress(page: Int)
    /// The last page was shown.
    case finished

    /// The rule Continue uses: started is `0 < progress < pageCount`, finished is a progress
    /// at or past the page count. A gallery whose page count is unknown (0) is never finished.
    public init(progress: Int, pageCount: Int) {
        if progress <= 0 {
            self = .unread
        } else if pageCount > 0, progress >= pageCount {
            self = .finished
        } else {
            self = .inProgress(page: progress)
        }
    }
}

// Reading progress and the Read button.
extension GalleryDetailModel {
    /// Unread until the stored progress is known.
    public var readingStatus: GalleryReadingStatus {
        GalleryReadingStatus(progress: readingProgress ?? 0, pageCount: pageCount)
    }

    /// The Read button: an unread gallery from page 1, one in progress where it was left, and a
    /// finished one from page 1 again. (Opening a finished gallery at its stored page would
    /// start on the last page, one swipe from the closing page.)
    public func read() {
        switch readingStatus {
        case .finished: openReader(page: 1)
        case .unread, .inProgress: openReader()
        }
    }

    /// Follows the stored progress while the model exists. The reader writes it once it has
    /// rested on a page, so this sees a value per rest, not per page turn.
    func followReadingProgress() {
        let progress = database.observeReadingProgress(gid: gallery.gid)
        tasks.run("readingProgress") { [weak self] in
            do {
                for try await value in progress {
                    guard let self else { return }
                    if readingProgress != value { readingProgress = value }
                }
            } catch {
                // Cancelled with the model, or the database failed: the last value stays.
            }
        }
    }
}
