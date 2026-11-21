import EhCore
import EhModels
import Foundation

// Page translation in the reader: what the controls read and do, forwarded to the
// `ReaderTranslationModel` the reader owns, and what that model asks of the reader.
extension ReaderModel: ReaderTranslationHost {
    /// Whether the controls each design reserves for translation are shown, and what a press
    /// of Translate does.
    public var translationAvailability: ReaderTranslationAvailability {
        translation.availability(isOtherLanguage: isMarkedOtherLanguage)
    }

    /// Translate: on, off, or the download sheet when the models are not installed.
    public func toggleTranslation() {
        guard translationAvailability != .unavailable else { return }
        translation.press()
    }

    /// The Retry of "Couldn't translate page 23".
    public func retryTranslation() {
        translation.retryCurrentPage()
    }

    /// What the engine shows over its pages: it reads this when it attaches, and is told
    /// every change through `ReaderEngineCommands.setTranslationDisplay`.
    public var translationDisplay: ReaderTranslationDisplay {
        translation.display
    }

    /// The engine's data source: a page's overlay, or `nil`.
    public func translationOverlay(at page: Int) -> PageTranslationOverlay? {
        translation.overlay(at: page)
    }

    /// The engine could not read a page's patch file; the page is drawn again.
    public func translationOverlayDidFail(page: Int) {
        translation.overlayDidFail(page: page)
    }

    /// The site's language and the titles' language groups. The detail's language is the
    /// site's own field; a list's gallery has only its tags.
    var isMarkedOtherLanguage: Bool {
        let titles = [parsedTitles?.title, parsedTitles?.japaneseTitle].compactMap(\.self)
        return ReaderTranslationLanguage.isOtherLanguage(site: detail?.language ?? gallery.language, titles: titles)
    }

    func translationFirstPageDidShow() {
        translation.firstPageDidShow(isOtherLanguage: isMarkedOtherLanguage)
    }

    // MARK: ReaderTranslationHost

    func translationImageURL(of page: Int) -> URL? {
        if case .image(let url) = pageState(at: page) { return url }
        return nil
    }

    func translationNeedsModels() {
        destination = .translationDownload
    }
}
