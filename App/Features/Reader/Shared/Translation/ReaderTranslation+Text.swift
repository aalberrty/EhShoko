import EhCore
import EhFeatures

// What the reader's translation controls say, the same in every design (`README` 7.5 and
// 8): the current page's status, a download under way, and what VoiceOver reads for the
// Translate control. Each design places the texts in its own capsule, toast or line.

private typealias Strings = L10n.Localizable.Reader.Translate

extension ReaderTranslationStatus {
    /// The status line, or `nil` where the design shows none.
    ///
    /// A page that is done (`.translated`, or `.nothingToDraw`) has a line only where the
    /// design asks for one with `showsDone`: Shelf's capsule names the target and how to see
    /// the original ("简体中文 · Hold Translate to see the original"). Wall's pill and Ledger's
    /// segmented control are already how to see the original, so their toast and line show
    /// nothing for a page that is done.
    func text(showsDone: Bool) -> String? {
        switch self {
        case .gettingReady: Strings.Status.preparing
        case .translating(let page): Strings.Status.translating(page)
        case .failed(let page): Strings.Status.failed(page)
        case .translated, .nothingToDraw: showsDone ? Self.doneText : nil
        }
    }

    /// Whether the line offers Retry (`ReaderModel.retryTranslation()`).
    var offersRetry: Bool {
        if case .failed = self { true } else { false }
    }

    /// Whether the line shows work under way, for a design that draws a spinner beside it.
    var isWorking: Bool {
        switch self {
        case .gettingReady, .translating: true
        case .translated, .nothingToDraw, .failed: false
        }
    }

    /// Shelf's line for a page that is done.
    static var doneText: String {
        "\(Strings.target) · \(Strings.Status.hold)"
    }

    /// Retry's title: the error view's "Try again".
    static var retryTitle: String {
        L10n.Localizable.ErrorView.Button.retry
    }
}

extension ReaderTranslationAvailability {
    /// A line for the control while the models download or are prepared
    /// ("Downloading translation · 412 MB of 1.18 GB"), or `nil` in the other cases.
    var installingText: String? {
        guard case .installing(let progress) = self else { return nil }
        guard let progress else { return Strings.Status.preparing }
        return Strings.Status.downloading(progress.completedBytes.byteText, progress.totalBytes.byteText)
    }

    /// How far the download is, for a design's progress ring; `nil` while nothing downloads.
    var downloadFraction: Double? {
        guard case .installing(let progress?) = self else { return nil }
        return progress.fraction
    }
}

/// What VoiceOver reads for a design's Translate control: "Translate", then whether it is on
/// and how many pages of the gallery were translated before ("Translate, Translation off,
/// 12 pages already translated"), and the download while one is under way. The mark itself
/// is drawn, not read on its own: it is part of the button (`README` 8).
struct ReaderTranslateAccessibility: Equatable {
    let isOn: Bool
    let pagesTranslatedBefore: Int
    let availability: ReaderTranslationAvailability

    var label: String { L10n.Localizable.Reader.translate }

    var value: String {
        var parts = [isOn ? Strings.A11y.on : Strings.A11y.off]
        if let cached = Self.cachedText(pagesTranslatedBefore) { parts.append(cached) }
        if let installing = availability.installingText { parts.append(installing) }
        return parts.joined(separator: ", ")
    }

    /// "12 pages already translated", "1 page already translated", or `nil` for none.
    static func cachedText(_ count: Int) -> String? {
        switch count {
        case ...0: nil
        case 1: Strings.A11y.Cached.one
        default: Strings.A11y.cached(count)
        }
    }
}
