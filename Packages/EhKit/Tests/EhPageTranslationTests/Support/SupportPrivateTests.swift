@testable import EhPageTranslation
import Foundation
import Testing

/// The opt-in tier for `Support/`: real pages and real model files from the private folder.
@Suite(.privateFolder) struct SupportPrivateTests {
    /// The research's 18 test pages: 17 as the PNG files the research read, 15 of those also as
    /// the WebP files the site sent. Their sizes are in the research's truth files.
    static let pngPages = "research/mt-spike/ocr/pages"
    static let webPPages = "research/mt-spike/eh/pages"
    static let truth = "research/mt-det/truth"
    static let translator = "models/jmt/dl"

    private struct Truth: Decodable {
        let size: [Int]
    }

    @Test func everyResearchPageDecodesAtItsSize() throws {
        let folder = try PrivateFolder.required()
        let pages = try folder.files(in: Self.pngPages, withExtensions: ["png"])
            + folder.files(in: Self.webPPages, withExtensions: ["webp"])
        #expect(pages.count == 32)
        for url in pages {
            let name = url.deletingPathExtension().lastPathComponent
            let truth = try JSONDecoder().decode(
                Truth.self, from: Data(contentsOf: folder.url("\(Self.truth)/\(name).json"))
            )
            let page = try PageImage(data: Data(contentsOf: url))
            #expect([page.width, page.height] == truth.size, "\(name)")
            #expect(!page.isReduced)
            #expect(page.colorSpace.model == .rgb)
        }
    }

    /// The research decoded the site's WebP files with PIL and worked on the PNG copies; the app
    /// decodes the WebP files with ImageIO. This says how far apart the two are.
    @Test func imageIOSeesTheSitesWebPAsTheResearchSawIt() throws {
        let folder = try PrivateFolder.required()
        var largest = 0, differing = 0, total = 0
        for webP in try folder.files(in: Self.webPPages, withExtensions: ["webp"]) {
            let name = webP.deletingPathExtension().lastPathComponent
            let app = try PageImage(data: Data(contentsOf: webP))
            let research = try PageImage(data: Data(contentsOf: folder.url("\(Self.pngPages)/\(name).png")))
            try #require(app.width == research.width && app.height == research.height)
            app.pixels.withUnsafeBytes { a in
                research.pixels.withUnsafeBytes { b in
                    for index in 0..<a.count where index % 4 != 3 {
                        let difference = abs(Int(a[index]) - Int(b[index]))
                        largest = max(largest, difference)
                        if difference != 0 { differing += 1 }
                        total += 1
                    }
                }
            }
        }
        let share = Double(differing) / Double(max(total, 1))
        #expect(largest <= Self.webPTolerance, "largest difference \(largest), \(share * 100)% of values differ")
    }

    /// Measured on the development Mac: see `imageIOSeesTheSitesWebPAsTheResearchSawIt`.
    static let webPTolerance = 0

    @Test func aLowerCapReducesARealPageAndKeepsItsShape() throws {
        let folder = try PrivateFolder.required()
        let url = try #require(try folder.files(in: Self.pngPages, withExtensions: ["png"]).first)
        let page = try PageImage(data: Data(contentsOf: url), maximumPixelCount: 1_000_000)
        #expect(page.isReduced)
        #expect(page.width * page.height <= 1_000_000 && page.width * page.height > 990_000)
        let shape = Double(page.width) / Double(page.height)
        let original = Double(page.originalWidth) / Double(page.originalHeight)
        #expect(abs(shape / original - 1) < 0.005)
    }

    @Test func theTranslatorsEmbeddingTablesOpenWithTheShapesOfItsConfiguration() throws {
        let folder = try PrivateFolder.required()
        struct Config: Decodable {
            let vocab: Int
            let maxTgt: Int
        }
        struct Host: Decodable {
            let heads: Int
            let headDim: Int
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let config = try decoder.decode(
            Config.self, from: Data(contentsOf: folder.url("\(Self.translator)/config.json"))
        )
        let host = try decoder.decode(
            Host.self, from: Data(contentsOf: folder.url("\(Self.translator)/coreml/host/host.json"))
        )
        let width = host.heads * host.headDim
        let encoderTable = try NPYTable(url: folder.url("\(Self.translator)/coreml/host/enc_emb.npy"))
        let decoderTable = try NPYTable(url: folder.url("\(Self.translator)/coreml/host/dec_emb.npy"))
        let positions = try NPYTable(url: folder.url("\(Self.translator)/coreml/host/pos.npy"))
        #expect(decoderTable.rows == config.vocab && positions.rows == config.maxTgt)
        let columns = [encoderTable.columns, decoderTable.columns, positions.columns]
        #expect(columns.allSatisfy { $0 == width })
        var row = [Float](repeating: 0, count: width)
        for table in [encoderTable, decoderTable, positions] {
            for index in [0, table.rows / 2, table.rows - 1] {
                row.withUnsafeMutableBufferPointer { if let base = $0.baseAddress { table.floatRow(index, into: base) } }
                let finite = row.allSatisfy { $0.isFinite }, nonZero = row.contains { $0 != 0 }
                #expect(finite && nonZero)
            }
        }
    }
}
