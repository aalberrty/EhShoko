import EhModels
import Foundation

/// The gallery's titles split into the parts of the site's naming convention.
nonisolated public struct ReaderParsedTitles: Equatable, Sendable {
    public var title: ParsedTitle
    /// The Japanese title's parts, when the gallery has one.
    public var japaneseTitle: ParsedTitle?

    public init(title: ParsedTitle, japaneseTitle: ParsedTitle?) {
        self.title = title
        self.japaneseTitle = japaneseTitle
    }

    /// The parts of the title the gallery page shows: the Japanese one when preferred and
    /// present.
    public func preferred(japanese prefersJapanese: Bool) -> ParsedTitle {
        prefersJapanese ? japaneseTitle ?? title : title
    }
}

// The titles the controls show.
extension ReaderModel {
    /// The title the gallery page shows: the Japanese title when preferred and present, else
    /// the detail's title; the list's title until a detail is known.
    public func title(prefersJapanese: Bool) -> String {
        detail?.title(prefersJapanese: prefersJapanese) ?? gallery.title
    }

    /// The title in its parts, parsed off the main actor when the reader starts. Until then
    /// (a few milliseconds after the first page can show), the whole title as its core.
    public func parsedTitle(prefersJapanese: Bool) -> ParsedTitle {
        parsedTitles?.preferred(japanese: prefersJapanese) ?? ParsedTitle(raw: title(prefersJapanese: prefersJapanese))
    }

    /// The title without the groups the site's convention puts around it ("Yoake no Hakoniwa"
    /// of "[Circle (Artist)] Yoake no Hakoniwa [English]"), for a control with little room
    /// (Shelf's capsule, Ledger's sheet). A title outside the convention is returned whole.
    public func shortTitle(prefersJapanese: Bool) -> String {
        parsedTitle(prefersJapanese: prefersJapanese).core
    }

    /// Parses the titles known now: the detail's, else the list's.
    func parseTitles() async {
        let title = detail?.title ?? gallery.title
        let japaneseTitle = detail?.jpnTitle
        let parsed = await Self.parse(title: title, japaneseTitle: japaneseTitle)
        guard !isClosed, parsed != parsedTitles else { return }
        parsedTitles = parsed
    }

    @concurrent
    nonisolated private static func parse(title: String, japaneseTitle: String?) async -> ReaderParsedTitles {
        ReaderParsedTitles(title: TitleParser.parse(title), japaneseTitle: japaneseTitle.map(TitleParser.parse))
    }
}
