import EhModels

/// A reader to open over the browsing UI, presented by whoever holds the request (the shell
/// for Continue).
nonisolated public struct ReadingRequest: Hashable, Identifiable, Sendable {
    public let gallery: Gallery
    /// 1-based; `nil` opens at the stored reading progress.
    public let page: Int?

    public init(gallery: Gallery, page: Int? = nil) {
        self.gallery = gallery
        self.page = page
    }

    public var id: String { gallery.gid }
}
