import EhModels
@testable import EhPageTranslation
import Foundation
import Testing

@Suite struct JMTTranslatorTests {
    private func translator(_ networks: JMTStubNetworks) throws -> (JMTTranslator, JMTTestRelease) {
        let release = try JMTTestRelease()
        return (JMTTranslator(release: try JMTRelease(files: release.files), networks: networks), release)
    }

    @Test func givesOneResultForEachLineInOrder() async throws {
        let networks = JMTStubNetworks(script: [5, 2, 4, 2])
        let (translator, release) = try translator(networks)
        defer { release.remove() }
        let results = try await translator.translate(["アイ", "  ", "ア"])
        #expect(results == ["世界", nil, "你好"])
        // The blank line never reaches the networks.
        #expect(networks.encoderLengths.count == 2 && networks.calls.count == 4)
    }

    @Test func givesNilForALineTheModelLeavesEmpty() async throws {
        let (translator, release) = try translator(JMTStubNetworks(script: [2]))
        defer { release.remove() }
        #expect(try await translator.translate(["ア"]) == [nil])
        #expect(try await translator.translate([]) == [])
    }

    @Test func stopsBetweenLinesWhenCancelled() async throws {
        let networks = JMTStubNetworks(script: [2])
        let (translator, release) = try translator(networks)
        defer { release.remove() }
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await translator.translate(["ア", "イ"])
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(networks.calls.isEmpty)
    }
}

@Suite struct JMTReleaseTests {
    @Test func readsTheHostFiles() throws {
        let files = try JMTTestRelease()
        defer { files.remove() }
        let release = try JMTRelease(files: files.files)
        #expect(release.inputLengths == [4, 8])
        #expect((release.bos, release.eos, release.pad, release.sourcePad) == (1, 2, 3, 3))
        #expect(release.cacheLength == 4 && release.maximumTarget == 6 && release.crossLength == 10)
        #expect(release.kanaRules.first == .init(previous2: nil, previous1: 10, banned: [11, 12, 13]))
        #expect(release.kanaRules[1].previous2 == 10 && release.kanaRules[1].previous1 == 6)
    }

    @Test(arguments: [(1, 4), (4, 4), (5, 8), (8, 8), (12, 8)])
    func choosesTheInputLength(tokens: Int, length: Int) throws {
        let files = try JMTTestRelease()
        defer { files.remove() }
        #expect(try JMTRelease(files: files.files).inputLength(for: tokens) == length)
    }

    @Test func limitsTheStepsAsTheReleaseDoes() throws {
        let files = try JMTTestRelease()
        defer { files.remove() }
        let release = try JMTRelease(files: files.files)
        // min(3n + 10, max_tgt 6, T + 1 = 5)
        #expect(release.stepLimit(for: 3) == 5)
        #expect(release.stepLimit(for: 0) == 5)
    }

    @Test func refusesTablesThatDoNotMatchTheHeads() throws {
        let files = try JMTTestRelease(heads: 2)
        defer { files.remove() }
        #expect(throws: JMTError.self) { try JMTRelease(files: files.files) }
    }

    @Test func refusesAConfigurationWithoutItsSettings() throws {
        let files = try JMTTestRelease(configurationOverride: #"{"bos": 1}"#)
        defer { files.remove() }
        #expect(throws: JMTError.self) { try JMTRelease(files: files.files) }
    }

    @Test func findsTheFilesInTheReleasesLayout() {
        let files = JMTFiles(root: URL(filePath: "/models/mt-jmt-fast-1"))
        #expect(files.encoder.path == "/models/mt-jmt-fast-1/coreml/encoder_static_fp16.mlmodelc")
        #expect(files.decoder.path == "/models/mt-jmt-fast-1/coreml/decoder_fp16.mlmodelc")
        #expect(files.tokenizer.path == "/models/mt-jmt-fast-1/tokenizer/tokenizer.json")
        #expect(files.host.path == "/models/mt-jmt-fast-1/coreml/host/host.json")
    }
}
