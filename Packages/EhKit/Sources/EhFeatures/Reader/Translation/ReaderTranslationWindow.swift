import EhCore
import Foundation

/// The pages a reader would like translated for its current page, in order of priority
/// (`README` 4.2): the pages on screen, the next pages in reading order, the page before.
///
/// It always asks for the most the service may work on. How much of it is worked on (three
/// pages ahead or one, by translator; less under heat, in Low Power Mode or after a memory
/// warning) is the service's `PageTranslationPolicy`.
nonisolated public struct ReaderTranslationWindow: Sendable, Equatable {
    /// The most pages ahead any translator is given (`PageTranslationPolicy.pagesAhead(for:)`
    /// gives three to the Core ML translator).
    public static let pagesAhead = 3
    /// The most pages that count as on screen. Two in a spread; a strip of short pages can
    /// show more, and the service works on every page on screen whatever the phone's state.
    public static let maximumOnScreen = 4

    public var onScreen: [Int]
    public var ahead: [Int]
    public var behind: [Int]

    /// - Parameters:
    ///   - currentPage: The page the engine reports as current, 1-based.
    ///   - pageCount: Pages past the end are never asked for, nor is the closing page.
    ///   - shown: The pages the engine shows, nearest first: both pages of a spread, or every
    ///     page of the strip that is partly on screen. They count while the current page is
    ///     among them. Otherwise the engine has not said yet what it shows, and the current
    ///     page stands for them.
    public init(currentPage: Int, pageCount: Int, shown: [Int] = []) {
        guard pageCount > 0, (1...pageCount).contains(currentPage) else {
            onScreen = []
            ahead = []
            behind = []
            return
        }
        var seen = Set<Int>()
        var pages = shown.filter { (1...pageCount).contains($0) && seen.insert($0).inserted }
        if !pages.contains(currentPage) {
            pages = [currentPage]
        }
        onScreen = Array(pages.prefix(Self.maximumOnScreen))
        let first = onScreen.min() ?? currentPage
        let last = onScreen.max() ?? currentPage
        let lastAhead = min(last + Self.pagesAhead, pageCount)
        ahead = last < lastAhead ? Array((last + 1)...lastAhead) : []
        behind = first > 1 ? [first - 1] : []
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
