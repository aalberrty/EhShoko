@testable import EhModels
import Testing

/// Keeps the table of measured figures whole: a choice without figures, a choice missing a row
/// its kind has, or a tally that cannot be right fails here, on every run.
@Suite struct PageTranslationMeasurementsTests {
    private typealias Kind = MeasuredFigure.Kind
    private typealias Subject = PageTranslationMeasurements.Subject

    // The rows each kind of choice shows, in order. Adding a kind of figure to one choice means
    // adding it here, and then to every other choice of that kind, as `.notMeasured` if need be.
    private static let detectorRows: [Kind] = [.balloonTextFound, .notesFound, .timePerPage, .memory, .firstLoad]
    private static let readerRows: [Kind] = [.linesReadExactly, .timePerBlock, .memory, .firstLoad]
    private static let translatorRows: [Kind] = [
        .linesFullyRight, .linesWithSeriousError, .timePerPage, .memory, .graphicsMemory, .firstLoad, .heat,
    ]
    private static let repaintModelRows: [Kind] = [.pictureMatches, .timePerTile, .memory, .firstLoad]
    /// "Off" runs no model: all it has is the time for a page.
    private static let repaintOffRows: [Kind] = [.timePerPage]
    /// With the switch for sound effects off, then on.
    private static let pairRows: [Kind] = [.linesReadExactly, .linesReadExactlyWithSoundEffects]

    /// What the figures are counted on: on the 17 test pages that exist (the research's 18
    /// without p2), 77 balloon texts and 55 notes, 130 lines of dialogue and 88 judged lines;
    /// 10 tiles of artwork on the phone.
    private static let totals: [Kind: Int] = [
        .balloonTextFound: 77, .notesFound: 55, .linesReadExactly: 130, .linesReadExactlyWithSoundEffects: 130,
        .linesFullyRight: 88, .linesWithSeriousError: 88, .pictureMatches: 10,
    ]

    private static let pairs = TextDetectorChoice.allCases.flatMap { detector in
        TextReaderChoice.allCases.map { Subject.pair(detector, $0) }
    }

    private static let subjects: [Subject] = TextDetectorChoice.allCases.map(Subject.detector)
        + TextReaderChoice.allCases.map(Subject.reader)
        + TranslatorChoice.allCases.map(Subject.translator)
        + RepaintChoice.allCases.map(Subject.repaint)
        + pairs

    private static func expectedRows(_ subject: Subject) -> [Kind] {
        switch subject {
        case .detector: detectorRows
        case .reader: readerRows
        case .translator: translatorRows
        case let .repaint(choice): choice.artifact == nil ? repaintOffRows : repaintModelRows
        case .pair: pairRows
        }
    }

    @Test func everyChoiceAndEveryPairHasTheRowsOfItsKind() {
        for subject in Self.subjects {
            let kinds = PageTranslationMeasurements.figures(of: subject).map(\.kind)
            #expect(kinds == Self.expectedRows(subject), "\(subject)")
        }
    }

    @Test func thePublicAccessorsGiveEachChoiceItsRows() {
        for choice in TextDetectorChoice.allCases {
            #expect(PageTranslationMeasurements.figures(for: choice) == PageTranslationMeasurements.figures(of: .detector(choice)))
        }
        for choice in TextReaderChoice.allCases {
            #expect(PageTranslationMeasurements.figures(for: choice) == PageTranslationMeasurements.figures(of: .reader(choice)))
        }
        for choice in TranslatorChoice.allCases {
            #expect(PageTranslationMeasurements.figures(for: choice) == PageTranslationMeasurements.figures(of: .translator(choice)))
        }
        for choice in RepaintChoice.allCases {
            #expect(PageTranslationMeasurements.figures(for: choice) == PageTranslationMeasurements.figures(of: .repaint(choice)))
        }
        for case let .pair(detector, reader) in Self.pairs {
            let off = PageTranslationMeasurements.linesReadExactly(detector: detector, reader: reader)
            let on = PageTranslationMeasurements.linesReadExactly(detector: detector, reader: reader, withSoundEffects: true)
            #expect(PageTranslationMeasurements.figures(of: .pair(detector, reader)) == [off, on])
        }
    }

    @Test func theTableHoldsNothingElse() {
        let described = Self.subjects.reduce(0) { $0 + PageTranslationMeasurements.figures(of: $1).count }
        #expect(described == PageTranslationMeasurements.table.count)
        let keys = PageTranslationMeasurements.table.map { "\($0.subject) \($0.figure.kind)" }
        #expect(Set(keys).count == keys.count)
    }

    @Test func talliesAreCountedOnTheResearchsTotals() {
        for row in PageTranslationMeasurements.table {
            let figure = row.figure
            switch figure.value {
            case let .tally(count, of: total):
                #expect(Self.totals[figure.kind] == total, "\(row.subject) \(figure.kind)")
                #expect((0...total).contains(count), "\(row.subject) \(figure.kind)")
            case .notMeasured:
                break
            default:
                #expect(Self.totals[figure.kind] == nil, "\(row.subject) \(figure.kind) is a count")
            }
        }
    }

    @Test func everyValueIsOfItsKindsSort() {
        for row in PageTranslationMeasurements.table {
            let figure = row.figure
            let fits = switch (figure.kind, figure.value) {
            case (_, .notMeasured): true
            case (.timePerPage, let .seconds(s)), (.timePerBlock, let .seconds(s)),
                 (.timePerTile, let .seconds(s)), (.firstLoad, let .seconds(s)): s > 0
            case (.memory, let .megabytes(mb)): mb > 0
            case (.graphicsMemory, let .megabytes(mb)): mb >= 0
            case (.heat, let .coolFor(pages)): pages > 0
            case (.heat, let .hotFrom(page)): page > 0
            case (_, .tally): Self.totals[figure.kind] != nil
            default: false
            }
            #expect(fits, "\(row.subject) \(figure.kind): \(figure.value)")
        }
    }

    /// Accuracy is counted on the test pages; speed, memory and heat on a device.
    @Test func everyFigureNamesWhatItWasMeasuredOn() {
        for row in PageTranslationMeasurements.table {
            let figure = row.figure
            let onPages = [.pagesPhone, .pagesMac].contains(figure.basis)
            let accuracy = Self.totals[figure.kind] != nil && figure.kind != .pictureMatches
            #expect(onPages == accuracy, "\(row.subject) \(figure.kind) on \(figure.basis)")
        }
    }

    /// What the app reads with the default pair on the 17 pages, as the opt-in tier scored it:
    /// more with the switch for sound effects on.
    @Test func theDefaultPairReadsWhatThePipelineReads() {
        let set = PageTranslationModelSet.default
        let off = PageTranslationMeasurements.linesReadExactly(detector: set.detector, reader: set.reader)
        let on = PageTranslationMeasurements.linesReadExactly(detector: set.detector, reader: set.reader, withSoundEffects: true)
        #expect(off == MeasuredFigure(kind: .linesReadExactly, value: .tally(83, of: 130), basis: .pagesMac))
        #expect(on == MeasuredFigure(kind: .linesReadExactlyWithSoundEffects, value: .tally(97, of: 130), basis: .pagesMac))
        #expect(PageTranslationMeasurements.testPageCount == 17)
    }

    /// ogkalu v4-s has no sound-effect class: the switch changes nothing it reads.
    @Test func theSwitchChangesNothingForADetectorWithoutSoundEffects() {
        for reader in TextReaderChoice.allCases {
            let off = PageTranslationMeasurements.linesReadExactly(detector: .v4s, reader: reader)
            let on = PageTranslationMeasurements.linesReadExactly(detector: .v4s, reader: reader, withSoundEffects: true)
            #expect(off.value == on.value, "\(reader)")
        }
    }
}
