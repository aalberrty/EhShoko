import CoreML
@testable import EhPageTranslation
import Foundation
import Testing

struct GreedyDecodingTests {
    actor Steps {
        var calls: [(token: Int, position: Int)] = []
        func record(_ token: Int, _ position: Int) { calls.append((token, position)) }
    }

    @Test func eachStepIsFedTheLastChoiceUntilTheEndToken() async throws {
        let script = [17, 9, 40, 3, 99]
        let steps = Steps()
        let tokens = try await GreedyDecoding(start: 2, end: 3, maximumSteps: 128).run { token, position in
            await steps.record(token, position)
            return script[position]
        }
        #expect(tokens == [17, 9, 40])
        let calls = await steps.calls
        #expect(calls.map(\.token) == [2, 17, 9, 40])
        #expect(calls.map(\.position) == [0, 1, 2, 3])
    }

    @Test func decodingStopsWhenTheCacheIsFull() async throws {
        let steps = Steps()
        let tokens = try await GreedyDecoding(start: 2, end: 3, maximumSteps: 128).run { token, position in
            await steps.record(token, position)
            return 10
        }
        #expect(tokens.count == 128)
        #expect(await steps.calls.count == 128)
        #expect(await steps.calls.last?.position == 127)
    }

    @Test func anImmediateEndReadsNothing() async throws {
        let tokens = try await GreedyDecoding(start: 2, end: 3, maximumSteps: 128).run { _, _ in 3 }
        #expect(tokens.isEmpty)
    }

    @Test func cancellationStopsBeforeTheNextStep() async throws {
        let steps = Steps()
        let task = Task {
            try await GreedyDecoding(start: 2, end: 3, maximumSteps: 128).run { token, position in
                await steps.record(token, position)
                if position == 2 { withUnsafeCurrentTask { $0?.cancel() } }
                return 10
            }
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(await steps.calls.count == 3)
    }
}

struct CPTDecoderStateTests {
    static let shape = CPTCacheShape(layers: 2, heads: 3, length: 8, width: 4, cacheType: .float16)

    static func state(_ shape: CPTCacheShape = shape) throws -> CPTDecoderState {
        try CPTDecoderState(shape, crossKeys: Tensors.zeros([2, 3, 5, 4]), crossValues: Tensors.zeros([2, 3, 5, 4]))
    }

    static func floats(_ array: MLMultiArray) -> [Float] {
        (0..<array.count).map { array[$0].floatValue }
    }

    @Test func theMaskOpensOnePositionAStep() throws {
        let state = try Self.state()
        #expect(Self.floats(state.mask).allSatisfy { $0 < -9000 })
        try state.prepare(token: 2, position: 0)
        #expect(state.token[0].intValue == 2 && state.position[0].intValue == 0)
        #expect(Self.floats(state.mask).allSatisfy { $0 < -9000 })
        try state.prepare(token: 51, position: 1)
        try state.prepare(token: 52, position: 2)
        #expect(state.token[0].intValue == 52 && state.position[0].intValue == 2)
        #expect(Self.floats(state.mask).map { $0 == 0 } == [true, true, false, false, false, false, false, false])
    }

    @Test(arguments: [false, true])
    func aStepsKeysGoIntoItsPositionOfTheCache(half: Bool) throws {
        let state = try Self.state()
        // (2, 3, 1, 4), last axis padded to 8, as the Neural Engine may return it.
        let values = (0..<24).map { Float($0) + 0.5 }
        let step = try Tensors.padded([2, 3, 1, 4], rowLength: 8, half: half, values: values)
        try state.store(keys: step, values: step, at: 5)
        for layer in 0..<2 {
            for head in 0..<3 {
                for k in 0..<4 {
                    let cached = state.keys[[layer, head, 5, k].map { NSNumber(value: $0) }].floatValue
                    #expect(cached == values[(layer * 3 + head) * 4 + k])
                    #expect(state.values[[layer, head, 5, k].map { NSNumber(value: $0) }].floatValue == cached)
                }
            }
        }
    }

    @Test func aStepOutsideTheCacheIsRefused() throws {
        let state = try Self.state()
        let step = try Tensors.zeros([2, 3, 1, 4])
        #expect(throws: ModelSignatureError.self) { try state.store(keys: step, values: step, at: 8) }
        #expect(throws: ModelSignatureError.self) { try state.store(keys: Tensors.zeros([2, 3, 1, 5]), values: step, at: 0) }
    }

    @Test func theNextTokenIsReadFromAnyIntegerType() throws {
        let int32 = try MLMultiArray(shape: [1], dataType: .int32)
        int32[0] = 417
        let float = try Tensors.make([1], values: [96])
        #expect(try CPTReader.nextToken(int32) == 417)
        #expect(try CPTReader.nextToken(float) == 96)
    }
}

struct CPTTextTests {
    /// Ids 0 to 4 are the special tokens.
    static let text = CPTText(vocabulary: ["[PAD]", "[UNK]", "[CLS]", "[SEP]", "[MASK]", "そ", "##れ", "は", "…", "・", ".", "A", "1", "!", " ", "？", "ー"])

    @Test func piecesJoinWithoutTheirMarksOrTheSpecialTokens() {
        #expect(Self.text.text([5, 6, 7]) == "それは")
        #expect(Self.text.text([2, 5, 1, 7, 3, 4, 0]) == "そは")
        #expect(Self.text.text([5, 99, 7]) == "そは")
    }

    @Test func whitespaceIsRemoved() {
        #expect(Self.text.text([5, 14, 7]) == "そは")
        #expect(CPTText.postprocess("そ れ\u{3000}は\n") == "それは")
    }

    @Test func dotsAreWrittenAsManga_OCRWritesThem() {
        #expect(CPTText.postprocess("…そ") == "．．．そ")
        #expect(CPTText.postprocess("そ・・") == "そ．．")
        #expect(CPTText.postprocess("そ・.・") == "そ．．．")
        #expect(CPTText.postprocess("そ・は") == "そ・は")
        #expect(CPTText.postprocess("そ.は") == "そ．は")
    }

    @Test func asciiBecomesFullWidth() {
        #expect(CPTText.postprocess("SEXは10!?") == "ＳＥＸは１０！？")
        #expect(Self.text.text([11, 12, 13, 15, 16]) == "Ａ１！？ー")
    }

    @Test func theVocabularyIsReadOneLineAnId() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "cpt-vocab-\(UUID().uuidString).txt")
        try "[PAD]\n[UNK]\n[CLS]\n[SEP]\n[MASK]\nそ\r\n##れ\n".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        let text = try CPTText(contentsOf: url)
        #expect(text.vocabulary.count == 8)
        #expect(text.text([5, 6]) == "それ")
    }
}
