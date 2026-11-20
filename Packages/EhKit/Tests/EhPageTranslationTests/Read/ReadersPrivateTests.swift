import CoreGraphics
import CoreML
@testable import EhPageTranslation
import Foundation
import ImageIO
import Testing

/// The opt-in tier for `Read/`: both readers on the research's 316 truth crops (each truth box
/// of the 18 pages with 4 pixels around it), on this Mac's CPU.
@Suite(.privateFolder, .serialized) struct ReadersPrivateTests {
    static let cpt = "models/det-phone/cpt"
    static let crops = "research/mt-det/ocr/crops"
    static let nar = "models/jmt/dl-ocr"

    struct Item: Decodable {
        let id: String
        let type: String
        let text: String
        let unsure: Bool
    }

    /// The 149 dialogue lines whose text is certain, by crop name (`page_index`).
    static func scoredLines() throws -> [String: String] {
        var lines: [String: String] = [:]
        for name in ReferenceSupport.pageNames {
            struct Truth: Decodable { let items: [Item] }
            let truth = try JSONDecoder().decode(
                Truth.self, from: Data(contentsOf: PrivateFolder.required().url("research/mt-det/truth/\(name).json"))
            )
            for item in truth.items where ["bubble", "free"].contains(item.type) && !item.unsure {
                lines[item.id.replacingOccurrences(of: "#", with: "_")] = item.text
            }
        }
        return lines
    }

    static func image(_ url: URL) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { throw CocoaError(.fileReadCorruptFile) }
        return image
    }

    static func cptReader(_ precision: String) async throws -> CPTReader {
        try await CPTReader.load(
            encoder: ReferenceSupport.compiledModel("\(cpt)/CPTEncoder-\(precision).mlpackage"),
            decoder: ReferenceSupport.compiledModel("\(cpt)/CPTDecoder-\(precision).mlpackage"),
            vocabulary: PrivateFolder.required().url("\(cpt)/vocab.txt"), computeUnits: .cpuOnly
        )
    }

    struct Reading: Decodable {
        let ids: [Int]
        let text: String
    }

    static func cptReference() throws -> [String: Reading] {
        try JSONDecoder().decode([String: Reading].self, from: Data(contentsOf: PrivateFolder.required().url("\(cpt)/swift-mac-fp32.json")))
    }

    /// Reads every research input (already 224 × 224, made by the research as manga-ocr makes
    /// them) and counts the readings equal to the research's.
    static func onResearchInputs(_ reader: CPTReader) async throws -> (tokens: Int, texts: Int, total: Int) {
        let reference = try cptReference()
        var tokens = 0, texts = 0
        for (name, expected) in reference {
            let read = try await reader.tokens(image(PrivateFolder.required().url("\(cpt)/inputs/\(name).png")))
            if read.tokens == expected.ids { tokens += 1 }
            if read.text == expected.text { texts += 1 }
        }
        return (tokens, texts, reference.count)
    }

    @Test func cptReadsTheResearchsTextOnItsInputs() async throws {
        let fp32 = try await Self.onResearchInputs(Self.cptReader("fp32"))
        ReferenceSupport.report("cpt2 fp32, research inputs: \(fp32.tokens)/\(fp32.total) token lists, \(fp32.texts) texts equal")
        #expect(fp32.total == 316 && fp32.tokens == 316 && fp32.texts == 316)
        let fp16 = try await Self.onResearchInputs(Self.cptReader("fp16"))
        ReferenceSupport.report("cpt2 fp16, research inputs: \(fp16.tokens)/\(fp16.total) token lists, \(fp16.texts) texts equal")
        // Measured on 2026-11-19: half precision on this Mac's CPU reads exactly what single precision does.
        #expect(fp16.tokens == 316 && fp16.texts == 316)
    }

    @Test func cptOnTheCropsWithThisCodesPreparation() async throws {
        let reader = try await Self.cptReader("fp16")
        let reference = try Self.cptReference(), lines = try Self.scoredLines()
        var same = 0, exact = 0, seconds: [Double] = []
        let clock = ContinuousClock()
        for (name, expected) in reference {
            let crop = try Self.image(PrivateFolder.required().url("\(Self.crops)/\(name).png"))
            let start = clock.now
            let text = try await reader.read(crop)
            seconds.append(ReferenceSupport.ms(clock.now - start))
            if text == expected.text { same += 1 }
            if let truth = lines[name], TextNormalisation.normalise(text) == TextNormalisation.normalise(truth) { exact += 1 }
        }
        ReferenceSupport.report(
            "cpt2 fp16, crops prepared here: \(same)/\(reference.count) equal the research's reading; "
                + "\(exact)/\(lines.count) dialogue lines exact (research: 143/149); "
                + String(format: "%.0f ms a crop (median, CPU)", DetectorsPrivateTests.median(seconds))
        )
        #expect(lines.count == 149)
        // Measured on 2026-11-19, as the research found with Swift's resize: 311 of 316, 143 of 149.
        #expect(same >= 311 && exact >= 143)
    }

    @Test func narSmallOnTheCrops() async throws {
        let reader = try await NARReader.load(
            compiledModel: ReferenceSupport.compiledModel("\(Self.nar)/coreml/mangaocr_nar_small_fp16.mlpackage"),
            vocabulary: PrivateFolder.required().url("\(Self.nar)/nar_vocabulary_6817.json"), computeUnits: .cpuOnly
        )
        struct Predictions: Decodable { let preds: [String: String] }
        let research = try JSONDecoder().decode(
            Predictions.self, from: Data(contentsOf: PrivateFolder.required().url("research/mt-det/ocr/pred_nar_small.json"))
        ).preds
        let lines = try Self.scoredLines()
        var same = 0, exact = 0, seconds: [Double] = []
        let clock = ContinuousClock()
        for (id, expected) in research {
            let name = id.replacingOccurrences(of: "#", with: "_")
            let crop = try Self.image(PrivateFolder.required().url("\(Self.crops)/\(name).png"))
            let start = clock.now
            let text = try await reader.read(crop)
            seconds.append(ReferenceSupport.ms(clock.now - start))
            if TextNormalisation.normalise(text) == TextNormalisation.normalise(expected) { same += 1 }
            if let truth = lines[name], TextNormalisation.normalise(text) == TextNormalisation.normalise(truth) { exact += 1 }
        }
        ReferenceSupport.report(
            "narSmall fp16: \(same)/\(research.count) equal the research's reading (its ONNX file, PIL's resize); "
                + "\(exact)/\(lines.count) dialogue lines exact (research: 126/149); "
                + String(format: "%.0f ms a crop (median, CPU)", DetectorsPrivateTests.median(seconds))
        )
        #expect(research.count == 316)
        // Measured on 2026-11-19 (the research's ONNX run read 126 of the 149 lines exactly).
        #expect(same >= 304 && exact >= 127)
    }
}

/// The research's `textnorm.py`, which every reading score used: NFKC; no whitespace; a run of
/// two or more of . ・ 。 as one …; dashes and the long-vowel mark as one ー; wave dashes as ~;
/// hearts as ♡.
enum TextNormalisation {
    static func normalise(_ text: String) -> String {
        var value = text.precomposedStringWithCompatibilityMapping
            .replacingOccurrences(of: "\u{FE0F}", with: "").replacingOccurrences(of: "\u{FE0E}", with: "")
        value = String(String.UnicodeScalarView(value.unicodeScalars.filter { !$0.properties.isWhitespace }))
        for (pattern, replacement) in [
            ("[.・。]{2,}", "…"), ("…+", "…"), ("[—―─‐–\\-－ー]+", "ー"), ("[〜～~]+", "~"), ("[♥❤♡]", "♡")
        ] {
            value = value.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
        }
        return value
    }
}
