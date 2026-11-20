import EhFeatures

/// Which pages a page label names: the page, or the two pages of a spread when the engine lays
/// out two side by side (`ReaderConfiguration.usesDualPage(in:)`). Shelf's capsule and Ledger's
/// open sheet read "Pages 22–23 of 48" with it.
struct ReaderSpreads: Equatable {
    /// In landscape, in a paged direction: where two pages can show.
    let offersDualPage: Bool
    let enablesDualPage: Bool
    let exceptCover: Bool

    var isDualPage: Bool { offersDualPage && enablesDualPage }

    func text(for position: ReaderPagePosition) -> String {
        guard isDualPage, !position.isAtEnd else { return position.long }
        let layout = ReaderSpreadLayout(pageCount: position.pageCount, isDualPage: true, exceptCover: exceptCover)
        let pages = layout.pages(inSpread: layout.spreadIndex(forPage: position.page))
        // A spread whose second page is the last reports that page; name the spread from its
        // first page whichever it reports.
        let first = ReaderPagePosition(page: pages.lowerBound, pageCount: position.pageCount, isAtEnd: false)
        return first.long(spreadEndingAt: pages.upperBound)
    }
}
