import EhCore
import EhFeatures
import UIKit

/// What the engine keeps for page translation.
struct ReaderEngineTranslation {
    /// What shows over the pages.
    var display = ReaderTranslationDisplay.original
    /// Whether pages are asked for their overlays: from the first display that is not the
    /// original. A reader in which Translate was never pressed asks for none.
    var asksForOverlays = false
    /// Pages whose overlay could not be shown, which the host has been told, until the host
    /// gives the page its translation again.
    var failedPages: Set<Int> = []
    /// The pages the reader is on, as last reported.
    var pagesOnScreen: [Int] = []
}

// The engine's side of page translation. A translated page keeps its image and gets an
// overlay above it (`ReaderTranslationOverlayView`); the engine asks its data source for a
// page's overlay and is told when one changes, as with page states. Nothing indexed by page
// changes for it: the page states, the prefetcher, the registry and decoding do not know it
// exists. The trailer is not a page and is never asked about.
extension ReaderEngineViewController {
    // MARK: Commands

    /// What shows over the pages: applied to the page views that exist, and to new ones. Not
    /// configuration: it rebuilds nothing, and from the second time on it only hides or shows
    /// the overlays that are loaded, so it can be sent while a finger moves.
    func setTranslationDisplay(_ display: ReaderTranslationDisplay) {
        guard display != translation.display else { return }
        translation.display = display
        // The wipe of `.compare` is not built yet: until then it shows the translation.
        let isDisplayed = display != .original
        if isDisplayed, !translation.asksForOverlays {
            translation.asksForOverlays = true
            content?.forEachPageView(configureTranslation(of:))
        } else {
            content?.forEachPageView { $0.setTranslationDisplayed(isDisplayed) }
        }
    }

    /// A page's translation changed: there is one now, another one, or none any more. A page
    /// without a view costs nothing; it is asked about when it gets one.
    func reloadTranslation(_ page: Int) {
        // What the host gives now is a new attempt: if it cannot be shown either, the host is
        // told again and decides (the reader's model draws a page again once, then marks it
        // failed).
        translation.failedPages.remove(page)
        guard translation.asksForOverlays, let pageView = content?.pageView(forPage: page) else { return }
        configureTranslation(of: pageView)
    }

    // MARK: Pages

    /// Gives a page view its page's overlay, for a new view and for a changed translation.
    func configureTranslation(of pageView: ReaderPageView) {
        guard translation.asksForOverlays, pageView.page >= 1 else { return }
        pageView.setTranslation(
            dataSource?.translationOverlay(at: pageView.page), isDisplayed: translation.display != .original
        )
    }

    /// Tells the host which pages the reader is on, when they changed. On the trailer alone
    /// there is none, and the host keeps those of the last page's place: nothing changes for
    /// what is indexed by page.
    func reportPagesOnScreen() {
        let pages = content?.pagesOnScreen ?? []
        guard !pages.isEmpty, pages != translation.pagesOnScreen else { return }
        translation.pagesOnScreen = pages
        delegate?.readerDidChangePagesOnScreen(pages)
    }

    // MARK: ReaderPageViewDelegate

    func pageView(_ pageView: ReaderPageView, didFailToShowTranslation overlay: PageTranslationOverlay) {
        let page = pageView.page
        // Once for each translation the host gives the page: a page view made again for the
        // same file does not tell it twice. Drawing again is the host's to limit.
        guard page >= 1, translation.failedPages.insert(page).inserted else { return }
        delegate?.readerDidFailToShowTranslation(page: page)
    }
}
