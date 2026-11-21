import EhCore
import EhModels

/// Whether the reader offers Translate for its gallery, and what a press of it does.
///
/// `ReaderTranslationSlot` keeps a design's translation controls out of the hierarchy while
/// it is `.unavailable`; in every other case they show.
nonisolated public enum ReaderTranslationAvailability: Hashable, Sendable {
    /// The site or the title marks the gallery as another language than Japanese.
    case unavailable
    /// No complete model set is installed: a press opens the download sheet. This is also
    /// the case when no source offers a model yet, which the sheet explains.
    case needsModels
    /// The models are downloading (`progress`), paused, waiting for a network, or being
    /// prepared (`progress` is `nil`). A press opens the download sheet.
    case installing(ModelTransferProgress?)
    /// A press turns Translate on.
    case ready

    /// The availability for a gallery in Japanese (or of no known language), from where the
    /// required models stand (`PageTranslationModelStore.requiredModelsState`).
    ///
    /// `ModelSetState.unavailable` means "no source offers a model": the gallery can still be
    /// translated once one does, so it is `.needsModels` here, not `.unavailable`.
    public init(_ state: ModelSetState) {
        switch state {
        case .ready:
            self = .ready
        case .unavailable, .missing, .failed:
            self = .needsModels
        case .downloading(let progress), .waitingForConnection(let progress), .paused(let progress):
            self = .installing(progress)
        case .preparing:
            self = .installing(nil)
        }
    }
}

/// The rule of which galleries are offered Translate: those that neither the site nor the
/// title marks as another language than Japanese.
nonisolated enum ReaderTranslationLanguage {
    /// Whether `site` (the gallery's `language:` tag, or the detail's language) or one of the
    /// titles' language groups ("[English]", "[中国翻訳]") names a language other than
    /// Japanese. A gallery that says nothing is offered Translate: Japanese galleries usually
    /// carry no language at all.
    static func isOtherLanguage(site: Language?, titles: [ParsedTitle]) -> Bool {
        if let site, site != .invalid, site != .japanese { return true }
        return titles.contains { title in
            guard let group = title.language, let language = TitleParser.language(named: group) else { return false }
            return language != .japanese
        }
    }
}
