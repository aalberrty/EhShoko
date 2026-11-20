@testable import EhModels
import Foundation
import Testing

/// The opt-in tier for the measured figures: the table in the private design document, between
/// its two markers, must equal the code's table row by row and in the same order. A number
/// changed in one place and not the other fails here.
@Suite struct MeasurementsDocumentTests {
    static let document = "README.md"

    @Test(.privateFolder) func theDocumentsTableEqualsTheCodes() throws {
        let folder = try PrivateFolder.required()
        let text = try String(contentsOf: folder.url(Self.document), encoding: .utf8)
        let document = try MeasurementsDocument.rows(in: text)
        let code = PageTranslationMeasurements.table.map(MeasurementsDocument.Row.init)

        let inCode = Dictionary(code.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        let inDocument = Dictionary(document.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        for row in document {
            #expect(inCode[row.key] == row, "document: \(row.line); code: \(inCode[row.key]?.line ?? "no row")")
        }
        for row in code where inDocument[row.key] == nil {
            #expect(Bool(false), "code has \(row.line); the document has no row")
        }
        #expect(document.count == inDocument.count, "the document names a row twice")
        #expect(code.count == inCode.count, "the code names a row twice")
        if Set(inCode.keys) == Set(inDocument.keys) {
            #expect(document.map(\.key) == code.map(\.key), "the rows are in a different order")
        }
    }

    @Test func aRowIsReadAsTheCodeWritesIt() throws {
        let text = """
        before
        <!-- measurements:begin -->
        | Role | Choice | Figure | Value | Basis | Note |
        |---|---|---|---|---|---|
        | detector | k2xl | balloonTextFound | 87/93 | pagesPhone | |
        | translator | hyMT2 | linesFullyRight | 57/101 | pagesMac | largerFile |
        | translator | jmtFast1 | heat | cool 40 | phone | |
        | translator | hyMT2 | heat | hot 11 | phone | |
        | reader | narSmall | memory | not measured | phone | |
        | translator | jmtFast1 | timePerPage | 0.30 s | phone | |
        | translator | jmtFast1 | graphicsMemory | 0 MB | phone | |
        | pair | v4s+cpt2 | linesReadExactly | not measured | pagesMac | |
        <!-- measurements:end -->
        | detector | k2xl | memory | 1 MB | phone | |
        """
        let rows = try MeasurementsDocument.rows(in: text)
        let expected: [(PageTranslationMeasurements.Subject, MeasuredFigure)] = [
            (.detector(.k2xl), .init(kind: .balloonTextFound, value: .tally(87, of: 93), basis: .pagesPhone)),
            (.translator(.hyMT2), .init(kind: .linesFullyRight, value: .tally(57, of: 101), basis: .pagesMac, note: .largerFile)),
            (.translator(.jmtFast1), .init(kind: .heat, value: .coolFor(pages: 40), basis: .phone)),
            (.translator(.hyMT2), .init(kind: .heat, value: .hotFrom(page: 11), basis: .phone)),
            (.reader(.narSmall), .init(kind: .memory, value: .notMeasured, basis: .phone)),
            (.translator(.jmtFast1), .init(kind: .timePerPage, value: .seconds(0.3), basis: .phone)),
            (.translator(.jmtFast1), .init(kind: .graphicsMemory, value: .megabytes(0), basis: .phone)),
            (.pair(.v4s, .cpt2), .init(kind: .linesReadExactly, value: .notMeasured, basis: .pagesMac)),
        ]
        #expect(rows == expected.map { MeasurementsDocument.Row(.init(subject: $0.0, figure: $0.1)) })
    }

    @Test(arguments: [
        "| detector | k2xl | balloonTextFound | 87 of 93 | pagesPhone | |",
        "| detector | k3 | memory | 59 MB | phone | |",
        "| detector | k2xl | memory | 59 GB | phone | |",
        "| detector | k2xl | memory | 59 MB | iPad | |",
        "| pair | k2xl | linesReadExactly | 1/149 | pagesMac | |",
        "| detector | k2xl | memory | 59 MB | phone | soon |",
        "| detector | k2xl | memory | 59 MB | phone |",
    ])
    func aRowTheCodeCannotHoldFails(line: String) {
        let text = "<!-- measurements:begin -->\n| h |\n|---|\n\(line)\n<!-- measurements:end -->"
        #expect(throws: MeasurementsDocument.Unreadable.self) { try MeasurementsDocument.rows(in: text) }
    }

    @Test func aDocumentWithoutTheMarkersFails() {
        #expect(throws: MeasurementsDocument.Unreadable.self) { try MeasurementsDocument.rows(in: "| a |") }
    }
}
