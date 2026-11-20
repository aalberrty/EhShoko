import CoreML
import Foundation

/// One network of the translator: Core ML in the app, a stub in tests.
protocol JMTNetwork: Sendable {
    func prediction(from input: any MLFeatureProvider) async throws -> any MLFeatureProvider
}

/// The translator's two networks: the encoder, one for each input length, and the one-step
/// decoder.
protocol JMTNetworks: Sendable {
    /// The encoder for input length `length`, once it is loaded.
    func encoder(length: Int) async throws -> any JMTNetwork
    var decoder: any JMTNetwork { get }
}

/// The names the release's Core ML conversion gives the networks' inputs and outputs.
enum JMTNames {
    /// The decoder's self-attention cache inputs, in the order of `steps`.
    static let caches = ["kc0", "vc0", "kc1", "vc1"]
    /// The decoder's outputs for the new position, written into `caches`.
    static let steps = ["k0", "v0", "k1", "v1"]
    /// The encoder's outputs and the decoder's inputs: cross-attention keys and values.
    static let cross = ["ck0", "cv0", "ck1", "cv1"]
}

/// The release's networks on Core ML. The shortest input length and the decoder are loaded
/// before the translator is handed out; the longer lengths load afterwards at low priority,
/// and a line that needs one first waits for it.
final class JMTCoreMLNetworks: JMTNetworks {
    let decoder: any JMTNetwork
    private let encoders: JMTEncoderLoader

    private init(decoder: any JMTNetwork, encoders: JMTEncoderLoader) {
        self.decoder = decoder
        self.encoders = encoders
    }

    deinit {
        let encoders = encoders
        Task { await encoders.cancel() }
    }

    static func load(
        files: JMTFiles, release: JMTRelease, computeUnits: MLComputeUnits, loadsLongerInputsAhead: Bool
    ) async throws -> JMTCoreMLNetworks {
        let encoders = JMTEncoderLoader(url: files.encoder, release: release, computeUnits: computeUnits)
        let shortest = release.inputLengths[0]
        async let first = encoders.encoder(length: shortest)
        let decoder = try await JMTCoreMLModel.load(
            contentsOf: files.decoder, computeUnits: computeUnits, expected: release.decoderSignature
        )
        _ = try await first
        if loadsLongerInputsAhead {
            await encoders.loadAhead(release.inputLengths.dropFirst())
        }
        return JMTCoreMLNetworks(decoder: decoder, encoders: encoders)
    }

    func encoder(length: Int) async throws -> any JMTNetwork {
        try await encoders.encoder(length: length)
    }
}

/// Loads each function of the multifunction encoder package once, on first need or ahead.
actor JMTEncoderLoader {
    private let url: URL
    private let release: JMTRelease
    private let computeUnits: MLComputeUnits
    private var loads: [Int: Task<JMTCoreMLModel, any Error>] = [:]

    init(url: URL, release: JMTRelease, computeUnits: MLComputeUnits) {
        self.url = url
        self.release = release
        self.computeUnits = computeUnits
    }

    func encoder(length: Int) async throws -> JMTCoreMLModel {
        try await load(length, priority: nil).value
    }

    /// Starts loading `lengths` at low priority, without waiting.
    func loadAhead(_ lengths: some Sequence<Int>) {
        for length in lengths { _ = load(length, priority: .utility) }
    }

    func cancel() {
        for load in loads.values { load.cancel() }
    }

    private func load(_ length: Int, priority: TaskPriority?) -> Task<JMTCoreMLModel, any Error> {
        if let load = loads[length] { return load }
        let (url, units, signature) = (url, computeUnits, release.encoderSignature(length: length))
        let load = Task(priority: priority) {
            try await JMTCoreMLModel.load(
                contentsOf: url, computeUnits: units, functionName: "L\(length)", expected: signature
            )
        }
        loads[length] = load
        return load
    }
}

extension JMTRelease {
    var width: Int { heads * headDimension }

    func encoderSignature(length: Int) -> JMTSignature {
        let cross = [1, heads, 2 + length, headDimension]
        return JMTSignature(
            inputs: ["x": [1, length, width], "kmask": [1, 1, 1, length]],
            outputs: Dictionary(uniqueKeysWithValues: JMTNames.cross.map { ($0, cross) })
        )
    }

    var decoderSignature: JMTSignature {
        var inputs = ["x": [1, 1, width], "smask": [1, 1, 1, cacheLength], "cmask": [1, 1, 1, crossLength]]
        for name in JMTNames.caches { inputs[name] = [1, heads, cacheLength, headDimension] }
        for name in JMTNames.cross { inputs[name] = [1, heads, crossLength, headDimension] }
        var outputs: [String: [Int]?] = ["logits": nil]
        for name in JMTNames.steps { outputs[name] = [1, heads, 1, headDimension] }
        return JMTSignature(inputs: inputs, outputs: outputs)
    }
}
