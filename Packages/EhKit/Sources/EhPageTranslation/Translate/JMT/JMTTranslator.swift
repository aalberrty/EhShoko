import CoreML
import Foundation

/// JMangaTranslator-Fast v1, the default translator: a 368M-parameter model made for manga
/// dialogue, on Core ML.
///
/// It translates one block at a time with no context, as its author requires, so the lines of
/// a page are independent. Calls may overlap: each page gets its own input buffers, and Core ML
/// runs concurrent predictions safely.
public struct JMTTranslator: PageTranslator {
    let release: JMTRelease
    let networks: any JMTNetworks

    init(release: JMTRelease, networks: any JMTNetworks) {
        self.release = release
        self.networks = networks
    }

    /// Reads the host files and loads the shortest input length and the decoder; the longer
    /// input lengths load afterwards at low priority unless `loadsLongerInputsAhead` is off,
    /// and are otherwise loaded by the first line that needs them.
    ///
    /// The first load on a phone builds the Neural Engine's program: about 9 s for these two,
    /// 28 s for all four. Later loads take 0.4 to 2.6 s.
    @concurrent
    public static func load(
        files: JMTFiles, computeUnits: MLComputeUnits = .cpuAndNeuralEngine, loadsLongerInputsAhead: Bool = true
    ) async throws -> JMTTranslator {
        let release = try JMTRelease(files: files)
        let networks = try await JMTCoreMLNetworks.load(
            files: files, release: release, computeUnits: computeUnits, loadsLongerInputsAhead: loadsLongerInputsAhead
        )
        return JMTTranslator(release: release, networks: networks)
    }

    @concurrent
    public func translate(_ lines: [String]) async throws -> [String?] {
        try await translateLines(lines).map { line in
            guard let line, !line.text.isEmpty else { return nil }
            return line.text
        }
    }

    /// Each line as the model made it; `nil` for a line with nothing to translate.
    func translateLines(_ lines: [String]) async throws -> [JMTLine?] {
        let decoding = try JMTDecoding(release: release)
        var results: [JMTLine?] = []
        results.reserveCapacity(lines.count)
        for line in lines {
            try Task.checkCancellation()
            if line.allSatisfy(\.isWhitespace) {
                results.append(nil)
            } else {
                results.append(try await decoding.translate(line, with: networks))
            }
        }
        return results
    }
}
