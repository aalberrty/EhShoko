import CoreML
@testable import EhPageTranslation
import Testing

/// The translator's networks are the shared Core ML wrapper, checked against what the
/// release's networks must look like before a line is translated.
@Suite struct JMTSignatureTests {
    static let signature = JMTSignature(inputs: ["x": [1, 32, 512]], outputs: ["logits": nil, "k0": [1, 8, 1, 64]])
    static let outputs: [String: FeatureShape] = [
        "logits": .multiArray(shape: [1, 1, 32000], type: .float16), "k0": .multiArray(shape: [1, 8, 1, 64], type: .float16)
    ]

    @Test func aModelWithTheExpectedInputsAndOutputsPasses() throws {
        try Self.signature.check(
            inputs: ["x": .multiArray(shape: [1, 32, 512], type: .float16), "extra": .other], outputs: Self.outputs,
            file: "L32"
        )
        // An output whose shape the description leaves open is not compared.
        var open = Self.outputs
        open["k0"] = .multiArray(shape: [], type: .float16)
        try Self.signature.check(inputs: ["x": .multiArray(shape: [1, 32, 512], type: .float16)], outputs: open, file: "L32")
    }

    @Test func aMissingOrDifferentInputIsABadFile() {
        #expect(throws: JMTError.self) {
            try Self.signature.check(inputs: [:], outputs: Self.outputs, file: "L32")
        }
        #expect(throws: JMTError.self) {
            try Self.signature.check(inputs: ["x": .multiArray(shape: [1, 64, 512], type: .float16)], outputs: Self.outputs, file: "L32")
        }
        // The loop writes raw halves: a float32 conversion is another file.
        #expect(throws: JMTError.self) {
            try Self.signature.check(inputs: ["x": .multiArray(shape: [1, 32, 512], type: .float32)], outputs: Self.outputs, file: "L32")
        }
        #expect(throws: JMTError.self) {
            try Self.signature.check(inputs: ["x": .image(width: 32, height: 512)], outputs: Self.outputs, file: "L32")
        }
    }

    @Test func aMissingOrDifferentOutputIsABadFile() {
        let inputs: [String: FeatureShape] = ["x": .multiArray(shape: [1, 32, 512], type: .float16)]
        #expect(throws: JMTError.self) {
            try Self.signature.check(inputs: inputs, outputs: ["logits": Self.outputs["logits"] ?? .other], file: "decoder")
        }
        var wrongShape = Self.outputs
        wrongShape["k0"] = .multiArray(shape: [1, 8, 2, 64], type: .float16)
        #expect(throws: JMTError.self) { try Self.signature.check(inputs: inputs, outputs: wrongShape, file: "decoder") }
        var wrongType = Self.outputs
        wrongType["logits"] = .multiArray(shape: [1, 1, 32000], type: .float32)
        #expect(throws: JMTError.self) { try Self.signature.check(inputs: inputs, outputs: wrongType, file: "decoder") }
    }
}
