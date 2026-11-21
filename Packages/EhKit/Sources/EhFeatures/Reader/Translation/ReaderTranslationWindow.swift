import EhCore
import Foundation

/// The pages a reader would like translated for its current page, in order of priority
/// (`README` 4.2): the page on screen, the next pages in reading order, the page before.
///
/// It always asks for the most the service may work on. How much of it is worked on (three
/// pages ahead or one, by translator; less under heat, in Low Power Mode or after a memory
/// warning) is the service's `PageTranslationPolicy`.
nonisolated public struct ReaderTranslationWindow: Sendable, Equatable {
    /// The most pages ahead any translator is given (`PageTranslationPolicy.pagesAhead(for:)`
    /// gives three to the Core ML translator).
    public static let pagesAhead = 3

    public var onScreen: [Int]
    public var ahead: [Int]
    public var behind: [Int]

    /// - Parameters:
    ///   - currentPage: The page the engine reports as current, 1-based. In a two-page spread
    ///     that is one of its pages; the other is the first page ahead or the page before.
    ///   - pageCount: Pages past the end are never asked for, nor is the closing page.
    public init(currentPage: Int, pageCount: Int) {
        guard pageCount > 0, (1...pageCount).contains(currentPage) else {
            onScreen = []
            ahead = []
            behind = []
            return
        }
        onScreen = [currentPage]
        let lastAhead = min(currentPage + Self.pagesAhead, pageCount)
        ahead = currentPage < lastAhead ? Array((currentPage + 1)...lastAhead) : []
        behind = currentPage > 1 ? [currentPage - 1] : []
    }

    /// Every page once, in order of priority.
    public var pages: [Int] { onScreen + ahead + behind }

    /// The service's window: each page with the image address the engine shows it from. A
    /// page whose address is not known yet is left out; it is sent once it resolves.
    public func request(imageURL: (Int) -> URL?) -> PageTranslationWindow {
        func pages(_ indices: [Int]) -> [PageTranslationPage] {
            indices.compactMap { index in imageURL(index).map { PageTranslationPage(index: index, imageURL: $0) } }
        }
        return PageTranslationWindow(onScreen: pages(onScreen), ahead: pages(ahead), behind: pages(behind))
    }
}
