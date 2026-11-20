import Foundation

/// One thing that was measured about a model the user can choose: what was measured, the
/// number, and what it was measured on. Plain values: the labels, units and headings are the
/// app's.
public struct MeasuredFigure: Sendable, Equatable {
    /// What was measured. A selection screen shows a choice's figures in the table's order.
    public enum Kind: String, Sendable, CaseIterable {
        /// Balloon texts whose ink the detector's boxes cover by at least half (of 93).
        case balloonTextFound
        /// Handwritten notes found the same way (of 58).
        case notesFound
        /// Lines of dialogue whose reading equals the truth (of 149).
        case linesReadExactly
        /// Lines a blind judge marked fully right (of 101).
        case linesFullyRight
        /// Lines a blind judge marked wrong, censored or dropped (of 101).
        case linesWithSeriousError
        case timePerPage
        /// Reading one block of text.
        case timePerBlock
        /// Repainting one 512 × 512 tile of artwork.
        case timePerTile
        /// The app's peak footprint in the run.
        case memory
        /// Metal's memory, for the language models.
        case graphicsMemory
        case firstLoad
        /// The thermal state over pages translated back to back.
        case heat
        /// Repainted tiles whose picture matches the Mac's (of 10).
        case pictureMatches
    }

    public enum Value: Sendable, Equatable {
        /// `count` of `total`.
        case tally(Int, of: Int)
        case seconds(Double)
        case megabytes(Int)
        /// The thermal state stayed below "serious" for this many pages in a row.
        case coolFor(pages: Int)
        /// The thermal state was "serious" from this page in a row on.
        case hotFrom(page: Int)
        /// Never measured: shown as such, never left out and never guessed.
        case notMeasured
    }

    /// What a figure was measured on.
    public enum Basis: String, Sendable, CaseIterable {
        /// Our test pages, scored from the phone's own output.
        case pagesPhone
        /// Our test pages, run on a Mac.
        case pagesMac
        /// The phone named by `PageTranslationMeasurements.phoneName`.
        case phone
        case mac
    }

    /// A caveat the figure carries.
    public enum Note: String, Sendable, CaseIterable {
        /// Judged on a larger file of the same model than the one the app downloads.
        case largerFile
    }

    public var kind: Kind
    public var value: Value
    public var basis: Basis
    public var note: Note?

    public init(kind: Kind, value: Value, basis: Basis, note: Note? = nil) {
        self.kind = kind
        self.value = value
        self.basis = basis
        self.note = note
    }
}

/// What was measured for every choice of page translation (`PageTranslationChoices`), for the
/// selection screens. A static table: nothing is read or computed until it is first asked for.
/// The rows are in `PageTranslationMeasurements+Table.swift`.
public enum PageTranslationMeasurements {
    /// The research's test pages, which every accuracy figure is counted on.
    public static let testPageCount = 18
    /// The phone that every `.phone` figure was measured on. A model name, not localized text.
    public static let phoneName = "iPhone 14 Pro Max"

    public static func figures(for choice: TextDetectorChoice) -> [MeasuredFigure] {
        figures(of: .detector(choice))
    }

    public static func figures(for choice: TextReaderChoice) -> [MeasuredFigure] {
        figures(of: .reader(choice))
    }

    public static func figures(for choice: TranslatorChoice) -> [MeasuredFigure] {
        figures(of: .translator(choice))
    }

    public static func figures(for choice: RepaintChoice) -> [MeasuredFigure] {
        figures(of: .repaint(choice))
    }

    /// Lines read exactly when the reader reads the detector's own boxes: the real pipeline.
    public static func linesReadExactly(
        detector: TextDetectorChoice, reader: TextReaderChoice
    ) -> MeasuredFigure {
        // The tests require a row for every pair; the fallback only keeps this total.
        figures(of: .pair(detector, reader)).first { $0.kind == .linesReadExactly }
            ?? MeasuredFigure(kind: .linesReadExactly, value: .notMeasured, basis: .pagesMac)
    }

    static func figures(of subject: Subject) -> [MeasuredFigure] {
        table.lazy.filter { $0.subject == subject }.map(\.figure)
    }

    /// What a row describes: one choice, or a detector and a reader together.
    enum Subject: Sendable, Hashable {
        case detector(TextDetectorChoice)
        case reader(TextReaderChoice)
        case translator(TranslatorChoice)
        case repaint(RepaintChoice)
        case pair(TextDetectorChoice, TextReaderChoice)
    }

    struct Row: Sendable, Equatable {
        var subject: Subject
        var figure: MeasuredFigure
    }
}
