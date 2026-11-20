import CoreML
@testable import EhPageTranslation
import Foundation
import Testing

/// The opt-in tier for the default translator: the real release against the research's
/// references, which were made on this Intel Mac with Core ML on the CPU (`.cpuOnly`). An Intel
/// Mac has no Neural Engine, so the same setting is used here.
@Suite(.privateFolder, .serialized) struct JMTPrivateTests {
    static let release = "models/jmt/dl"
    static let references = "research/mt-jmt/ref"

    private struct Reference: Decodable {
        struct Page: Decodable {
            let page: String
            let lines: [Line]
        }

        struct Line: Decodable {
            let n: Int
            let ja: String
            let zh: String
            let encIds: [Int]
            let outIds: [Int]
            let bucket: Int
        }

        let pages: [Page]
    }

    private static func decode<T: Decodable>(_ type: T.Type, _ path: String) throws -> T {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(type, from: Data(contentsOf: PrivateFolder.required().url(path)))
    }

    private static func files() throws -> JMTFiles {
        JMTFiles(root: try PrivateFolder.required().url(release))
    }

    @Test func theTokenizerGivesTheReferenceIDsForAllStrings() throws {
        let tokenizer = try JapaneseTokenizer(url: Self.files().tokenizer, maxLength: 256)
        let strings = try Self.decode([String].self, "\(Self.references)/tok/strings.json")
        let expected = try Self.decode([[Int]].self, "\(Self.references)/tok/strings_ref.json")
        try #require(strings.count == 561 && expected.count == 561)
        let differing = zip(strings, expected).filter { tokenizer.encode($0) != $1 }.map(\.0)
        #expect(differing.isEmpty, "\(differing.count) of 561 differ: \(differing.prefix(5))")
    }

    @Test func theDetokenizerGivesTheReferenceTextForAllLists() throws {
        let release = try JMTRelease(files: Self.files())
        let lists = try Self.decode([[Int]].self, "\(Self.references)/tok/idlists.json")
        let expected = try Self.decode([String].self, "\(Self.references)/tok/idlists_ref.json")
        try #require(lists.count == 603 && expected.count == 603)
        let differing = zip(lists, expected).filter { release.detokenizer.decode($0) != $1 }.map(\.0)
        #expect(differing.isEmpty, "\(differing.count) of 603 differ: \(differing.prefix(3))")
    }

    /// Tokenizing and detokenizing a line takes under 0.1 ms in an optimised build (the phone
    /// measured 0.02 ms). An unoptimised build is about ten times slower.
    #if DEBUG
    static let lineBudget = 1.0
    #else
    static let lineBudget = 0.1
    #endif

    @Test func tokenizingAndDetokenizingALineIsCheap() throws {
        let release = try JMTRelease(files: Self.files())
        let lines = try Self.decode(Reference.self, "\(Self.references)/swift-cpu.json").pages.flatMap(\.lines)
        let rounds = 20
        var checksum = 0
        let clock = ContinuousClock()
        let elapsed = clock.measure {
            for _ in 0..<rounds {
                for line in lines {
                    checksum &+= release.tokenizer.encode(line.ja).count
                    checksum &+= release.detokenizer.decode(line.outIds).utf8.count
                }
            }
        }
        let milliseconds = Double(elapsed.components.attoseconds) / 1e15 + Double(elapsed.components.seconds) * 1000
        let perLine = milliseconds / Double(rounds * lines.count)
        print("JMT tokenize + detokenize: \(String(format: "%.4f", perLine)) ms a line (checksum \(checksum))")
        #expect(perLine < Self.lineBudget)
    }

    @Test func translatesTheBakeOffLinesAsTheReference() async throws {
        let reference = try Self.decode(Reference.self, "\(Self.references)/swift-cpu.json")
        try await compare(reference, expectedLines: 139, label: "bake-off")
    }

    /// Ten long lines that use the 64 and 128 input lengths, the cut at 128 tokens and a full
    /// decode of 129 steps: the input lengths that load after the first.
    @Test func translatesTheLongLinesAsTheReference() async throws {
        let reference = try Self.decode(Reference.self, "\(Self.references)/long-swift-cpu.json")
        try await compare(reference, expectedLines: 10, label: "long")
    }

    private func compare(_ reference: Reference, expectedLines: Int, label: String) async throws {
        let compiled = FileManager.default.temporaryDirectory.appending(path: "jmt-compiled-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: compiled) }
        var files = try Self.files()
        files.encoder = try await Self.compile(files.encoder, into: compiled)
        files.decoder = try await Self.compile(files.decoder, into: compiled)
        let clock = ContinuousClock()
        let start = clock.now
        let translator = try await JMTTranslator.load(files: files, computeUnits: .cpuOnly)
        let loaded = clock.now - start
        let lines = reference.pages.flatMap(\.lines)
        try #require(lines.count == expectedLines)
        let translateStart = clock.now
        let results = try await translator.translateLines(lines.map(\.ja))
        let translated = clock.now - translateStart
        var same = 0
        for (line, result) in zip(lines, results) {
            let result = try #require(result)
            let equal = result.text == line.zh && result.outputIDs == line.outIds
                && result.sourceIDs == line.encIds && result.inputLength == line.bucket
            if equal { same += 1 } else { Issue.record("line \(line.n): \(result.text) ≠ \(line.zh)") }
        }
        print("JMT \(label): \(same) of \(lines.count) equal; load \(loaded), \(lines.count) lines \(translated)")
        #expect(same == lines.count)
    }

    /// The release ships packages; the store compiles them where these names point.
    private static func compile(_ compiledURL: URL, into folder: URL) async throws -> URL {
        let package = compiledURL.deletingPathExtension().appendingPathExtension("mlpackage")
        let temporary = try await MLModel.compileModel(at: package)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let destination = folder.appending(path: compiledURL.lastPathComponent)
        try FileManager.default.moveItem(at: temporary, to: destination)
        return destination
    }
}
