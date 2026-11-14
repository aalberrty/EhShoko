import EhFeatures

/// Where the reader is, as every design labels it: the slider's page (so a label follows a
/// scrub), the page count, and whether the closing page is current, where each design shows
/// "End" in place of the page (`Design/designs/closing-page.md`).
///
/// A value, so a label view that takes it redraws only when what it shows changes.
struct ReaderPagePosition: Equatable {
    let page: Int
    let pageCount: Int
    let isAtEnd: Bool

    init(page: Int, pageCount: Int, isAtEnd: Bool) {
        self.page = min(max(page, 1), max(pageCount, 1))
        self.pageCount = pageCount
        self.isAtEnd = isAtEnd
    }

    init(model: ReaderModel) {
        self.init(page: model.sliderPage, pageCount: model.pageCount, isAtEnd: model.isAtEnd)
    }

    /// "Page 23 of 48" (Shelf's capsule, Ledger's open sheet), or "End".
    var long: String {
        isAtEnd ? L10n.Localizable.Reader.end : L10n.Localizable.Reader.Page.of(page, pageCount)
    }

    /// "Pages 22–23 of 48", for two pages side by side, or "End".
    func long(spreadEndingAt last: Int) -> String {
        guard !isAtEnd else { return L10n.Localizable.Reader.end }
        let last = min(last, pageCount)
        return last > page ? L10n.Localizable.Reader.Pages.of(page, last, pageCount) : long
    }

    /// "23 / 48" (Wall's capsule, Ledger's resting sheet), or "End". The design sets the
    /// total in its own style, so the parts are separate.
    var current: String {
        isAtEnd ? L10n.Localizable.Reader.end : "\(page)"
    }

    var total: String { "\(pageCount)" }
}
