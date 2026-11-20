@testable import EhModels
import Foundation

/// Reads the table of measured figures from the design document: the Markdown table between
/// `<!-- measurements:begin -->` and `<!-- measurements:end -->`, with the columns Role,
/// Choice, Figure, Value, Basis and Note. Choices are named by their raw values; a pair is
/// `detector+reader`. Values are `87/93`, `0.343 s`, `59 MB`, `cool 40`, `hot 5` or
/// `not measured`.
enum MeasurementsDocument {
    static let begin = "<!-- measurements:begin -->"
    static let end = "<!-- measurements:end -->"

    struct Row: Equatable {
        typealias Subject = PageTranslationMeasurements.Subject

        let subject: Subject
        let figure: MeasuredFigure

        init(_ row: PageTranslationMeasurements.Row) {
            subject = row.subject
            figure = row.figure
        }

        /// Names the row: what it describes and what was measured.
        var key: String { "\(Self.role(subject)) | \(Self.choice(subject)) | \(figure.kind.rawValue)" }

        /// The row as the document writes it, for failure messages.
        var line: String {
            "| \(key) | \(Self.value(figure.value)) | \(figure.basis.rawValue) | \(figure.note?.rawValue ?? "") |"
        }

        static func role(_ subject: Subject) -> String {
            switch subject {
            case .detector: "detector"
            case .reader: "reader"
            case .translator: "translator"
            case .repaint: "repaint"
            case .pair: "pair"
            }
        }

        static func choice(_ subject: Subject) -> String {
            switch subject {
            case let .detector(choice): choice.rawValue
            case let .reader(choice): choice.rawValue
            case let .translator(choice): choice.rawValue
            case let .repaint(choice): choice.rawValue
            case let .pair(detector, reader): "\(detector.rawValue)+\(reader.rawValue)"
            }
        }

        static func value(_ value: MeasuredFigure.Value) -> String {
            switch value {
            case let .tally(count, total): "\(count)/\(total)"
            case let .seconds(seconds): "\(seconds) s"
            case let .megabytes(megabytes): "\(megabytes) MB"
            case let .coolFor(pages): "cool \(pages)"
            case let .hotFrom(page): "hot \(page)"
            case .notMeasured: "not measured"
            }
        }
    }

    struct Unreadable: Error, CustomStringConvertible {
        let description: String
    }

    /// The rows between the markers, in the document's order, without the header and the
    /// separator line.
    static func rows(in text: String) throws -> [Row] {
        guard let start = text.range(of: begin), let stop = text.range(of: end, range: start.upperBound..<text.endIndex)
        else { throw Unreadable(description: "the document has no \(begin) … \(end)") }
        let lines = text[start.upperBound..<stop.lowerBound]
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard lines.count >= 2 else { throw Unreadable(description: "the table has no header") }
        return try lines.dropFirst(2).map(row)
    }

    static func row(_ line: String) throws -> Row {
        let cells = line.split(separator: "|", omittingEmptySubsequences: false)
            .dropFirst().dropLast()
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard line.hasPrefix("|"), line.hasSuffix("|"), cells.count == 6 else { throw unreadable(line, "six cells") }
        let subject = try subject(role: cells[0], choice: cells[1], line: line)
        guard let kind = MeasuredFigure.Kind(rawValue: cells[2]) else { throw unreadable(line, "the figure") }
        guard let basis = MeasuredFigure.Basis(rawValue: cells[4]) else { throw unreadable(line, "the basis") }
        var note: MeasuredFigure.Note?
        if !cells[5].isEmpty {
            guard let named = MeasuredFigure.Note(rawValue: cells[5]) else { throw unreadable(line, "the note") }
            note = named
        }
        let figure = try MeasuredFigure(kind: kind, value: value(cells[3], line: line), basis: basis, note: note)
        return Row(.init(subject: subject, figure: figure))
    }

    private static func subject(role: String, choice: String, line: String) throws -> Row.Subject {
        func named<Choice: RawRepresentable<String>>(_ raw: some StringProtocol, as _: Choice.Type) throws -> Choice {
            guard let choice = Choice(rawValue: String(raw)) else { throw unreadable(line, "the choice") }
            return choice
        }
        switch role {
        case "detector": return try .detector(named(choice, as: TextDetectorChoice.self))
        case "reader": return try .reader(named(choice, as: TextReaderChoice.self))
        case "translator": return try .translator(named(choice, as: TranslatorChoice.self))
        case "repaint": return try .repaint(named(choice, as: RepaintChoice.self))
        case "pair":
            let parts = choice.split(separator: "+")
            guard parts.count == 2 else { throw unreadable(line, "detector+reader") }
            return try .pair(named(parts[0], as: TextDetectorChoice.self), named(parts[1], as: TextReaderChoice.self))
        default: throw unreadable(line, "the role")
        }
    }

    private static func value(_ text: String, line: String) throws -> MeasuredFigure.Value {
        if text == "not measured" { return .notMeasured }
        let tally = text.split(separator: "/")
        if tally.count == 2, let count = Int(tally[0]), let total = Int(tally[1]) { return .tally(count, of: total) }
        let words = text.split(separator: " ")
        guard words.count == 2 else { throw unreadable(line, "the value") }
        switch (words[0], words[1]) {
        case let (number, "s"): if let seconds = Double(number) { return .seconds(seconds) }
        case let (number, "MB"): if let megabytes = Int(number) { return .megabytes(megabytes) }
        case let ("cool", number): if let pages = Int(number) { return .coolFor(pages: pages) }
        case let ("hot", number): if let page = Int(number) { return .hotFrom(page: page) }
        default: break
        }
        throw unreadable(line, "the value")
    }

    private static func unreadable(_ line: String, _ what: String) -> Unreadable {
        Unreadable(description: "cannot read \(what) of \(line)")
    }
}
