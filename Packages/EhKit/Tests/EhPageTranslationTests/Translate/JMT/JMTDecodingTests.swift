@testable import EhPageTranslation
import Foundation
import Testing

/// The release's decoding loop with stub networks (`JMTStubNetworks`) and the test release.
@Suite struct JMTDecodingTests {
    private static let negative = Half.toFloat(Half.fromFloat(-1e4))

    private func translate(_ text: String, _ networks: JMTStubNetworks) async throws -> JMTLine {
        let release = try JMTTestRelease()
        defer { release.remove() }
        let decoding = try JMTDecoding(release: JMTRelease(files: release.files))
        return try await decoding.translate(text, with: networks)
    }

    @Test func runsTheEncoderAtTheShortestInputLengthThatHoldsTheLine() async throws {
        let networks = JMTStubNetworks(script: [2])
        // アイ is <s> アイ </s>: three ids.
        let line = try await translate("アイ", networks)
        #expect(line.sourceIDs == [1, 5, 2] && line.inputLength == 4)
        #expect(networks.encoderLengths == [4])
        #expect(networks.encoderMasks == [[0, 0, 0, Self.negative]])
        let longer = JMTStubNetworks(script: [2])
        #expect(try await translate("ウウウ", longer).inputLength == 8)
    }

    @Test func cutsALongLineToTheLongestInputLength() async throws {
        let networks = JMTStubNetworks(script: [2])
        let line = try await translate(String(repeating: "ウ", count: 10), networks)
        #expect(line.sourceIDs.count == 12 && line.inputLength == 8)
        #expect(networks.encoderMasks == [[Float](repeating: 0, count: 8)])
    }

    @Test func passesTheFirstTwoPlusNCrossPositionsAndZeroesTheRest() async throws {
        let networks = JMTStubNetworks(script: [2])
        _ = try await translate("アイ", networks)
        let call = try #require(networks.calls.first)
        #expect(call.cross == [1, 2, 3, 4, 5, 0, 0, 0, 0, 0])
        #expect(call.crossMask == [0, 0, 0, 0, 0] + [Float](repeating: Self.negative, count: 5))
    }

    @Test func stopsAtTheStepLimitAndKeepsTheCacheToItsLength() async throws {
        let networks = JMTStubNetworks(script: [5, 5, 5, 5, 5, 5, 5])
        let line = try await translate("アイ", networks)
        // min(3 · 3 + 10, max_tgt 6, T 4 + 1) = 5 steps.
        #expect(line.outputIDs == [5, 5, 5, 5, 5] && line.decoderCalls == 5)
        let calls = networks.calls
        #expect(calls[0].selfMask == [Float](repeating: Self.negative, count: 4))
        #expect(calls[2].selfMask == [0, 0, Self.negative, Self.negative])
        #expect(calls[2].cache == [1, 2, 0, 0])
        #expect(calls[4].selfMask == [0, 0, 0, 0] && calls[4].cache == [1, 2, 3, 4])
    }

    @Test func feedsTheTokenEmbeddingPlusThePositionRoundedToHalf() async throws {
        let networks = JMTStubNetworks(script: [5, 2])
        _ = try await translate("ア", networks)
        let calls = networks.calls
        // Step 0: <s> (0.25, 1) + position 0 (0, -1). Step 1: 5 (1.25, 1) + position 1 (0.125, -1).
        #expect(calls[0].x == [0.25, 0])
        #expect(calls[1].x == [1.375, 0])
    }

    @Test(arguments: [(2, "</s>"), (3, "<pad>")])
    func stopsAtTheEndOrPadToken(stop: Int, name: String) async throws {
        let line = try await translate("ア", JMTStubNetworks(script: [5, stop, 5]))
        #expect(line.outputIDs == [5] && line.decoderCalls == 2, "\(name)")
        #expect(line.text == "世界")
    }

    @Test func bansTheByteThatWouldCompleteAKana() async throws {
        // After byte E3, the bytes 81 to 83 would start hiragana or katakana: the runner-up wins.
        let line = try await translate("ア", JMTStubNetworks(script: [10, 11, 2], runnerUp: [1: 4]))
        #expect(line.outputIDs == [10, 4])
    }

    @Test func bansByTheLastTwoBytesWhereTheRuleNamesTwo() async throws {
        let afterBoth = try await translate("ア", JMTStubNetworks(script: [10, 6, 14, 2], runnerUp: [2: 5]))
        #expect(afterBoth.outputIDs == [10, 6, 5])
        let afterOne = try await translate("ア", JMTStubNetworks(script: [6, 14, 2], runnerUp: [1: 5]))
        #expect(afterOne.outputIDs == [6, 14])
    }

    @Test func takesTheFirstMaximumAsNumpyDoes() {
        #expect(JMTDecoding.firstMaximum([1, 3, 3, 2]) == 1)
        #expect(JMTDecoding.firstMaximum([1, .nan, 5]) == 1)
        #expect(JMTDecoding.firstMaximum([-.infinity, -.infinity]) == 0)
        #expect(JMTDecoding.firstMaximum([]) == 0)
    }
}
