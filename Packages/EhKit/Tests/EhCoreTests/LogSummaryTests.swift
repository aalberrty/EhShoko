import Foundation
import Testing
@testable import EhCore

@Suite struct LogSummaryTests {
    @Test func summariesCountLinesAndReadTheFirstAndLastDate() async throws {
        let directory = TemporaryLogDirectory()
        defer { directory.cleanUp() }
        try directory.writeFile(
            named: "Log-20240102-100000-000.log",
            contents: "2024-01-02 10:00:00.000 INFO a\r\n2024-01-03 11:00:00.000 INFO b\n\n\n2024-01-04 12:00:00.000 c\n",
            modified: Date(timeIntervalSince1970: 0)
        )
        try directory.writeFile(
            named: "Log-20240101-100000-000.log", contents: "", modified: Date(timeIntervalSince1970: 0)
        )
        try directory.writeFile(
            named: "Log-20231231-100000-000.log", contents: "nospace\n", modified: Date(timeIntervalSince1970: 0)
        )
        let logger = directory.makeLogger()

        let summaries = await logger.logSummaries()
        let byName = Dictionary(uniqueKeysWithValues: summaries.map { ($0.file.name, $0) })

        let full = try #require(byName["Log-20240102-100000-000.log"])
        #expect(full.recordCount == 3)
        #expect(full.firstDate == "2024-01-02")
        #expect(full.lastDate == "2024-01-04")
        let empty = try #require(byName["Log-20240101-100000-000.log"])
        #expect(empty.recordCount == 0)
        #expect(empty.firstDate == nil && empty.lastDate == nil)
        let undated = try #require(byName["Log-20231231-100000-000.log"])
        #expect(undated.recordCount == 1)
        #expect(undated.firstDate == nil)
    }

    /// The summary agrees with the lines the log viewer shows.
    @Test func theCountMatchesTheViewersLines() async throws {
        let directory = TemporaryLogDirectory()
        defer { directory.cleanUp() }
        let logger = directory.makeLogger()
        logger.info("one")
        logger.error("two\nstill two")
        logger.warning("three")
        await logger.flush()

        let summary = try #require(await logger.logSummaries().first)
        let lines = try await logger.lines(of: summary.file)

        #expect(summary.recordCount == lines.count)
        #expect(summary.firstDate == lines.first.map { String($0.prefix { $0 != " " }) })
        #expect(summary.lastDate == lines.last.map { String($0.prefix { $0 != " " }) })
    }
}
