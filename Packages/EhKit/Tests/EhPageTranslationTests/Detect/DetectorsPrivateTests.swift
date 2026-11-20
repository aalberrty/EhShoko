import CoreML
@testable import EhPageTranslation
import EhModels
import Foundation
import Testing

protocol RunnableDetector: TextDetector {
    func run(_ page: PageBitmap, in region: PixelRect) async throws -> DetectorRun
}

extension KoharuLayoutDetector: RunnableDetector {}
extension KoharuYOLODetector: RunnableDetector {}
extension OgkaluDetector: RunnableDetector {}
extension RTMDetDetector: RunnableDetector {}

/// The opt-in tier for `Detect/`: each detector on the research's 18 test pages, against the
/// research's references, on this Mac's CPU as the research ran them.
///
/// - The research's Mac rate: the fp32 model fed the research's own prepared input (so only
///   decoding can differ) matches its reference as the research's Swift code did.
/// - The shipped fp16 model on the same inputs, and on the pages themselves with this code's
///   preparation (17 pages: the 7 MP page p2 is missing from the folder), at least at the rates
///   the research measured on the phone.
@Suite(.privateFolder, .serialized) struct DetectorsPrivateTests {
    struct Case: Sendable {
        var name: String
        var fp16: String
        var fp32: String
        var inputs: String
        var placement: Letterbox.Placement
        var resampling: InputResampling
        var padding: UInt8
        var threshold: Double
        /// The reference boxes of a page.
        var reference: @Sendable (String) throws -> [ReferenceBox]
        /// A run's boxes in the reference's coordinates.
        var found: @Sendable (DetectorRun, PageBitmap) -> [ReferenceBox]
        var load: @Sendable (URL, MLComputeUnits) async throws -> any RunnableDetector
        /// Where the fp16 model runs on this Mac.
        var fp16Units: MLComputeUnits = .cpuOnly
    }

    static let root = "models/det-phone"

    static func normalised(_ run: DetectorRun, _ page: PageBitmap, kept: (Detection) -> Bool) -> [ReferenceBox] {
        run.detections.filter(kept).map {
            ReferenceBox($0.box, score: $0.score, label: $0.label, scaleX: 1000 / Double(page.width), scaleY: 1000 / Double(page.height))
        }
    }

    static func inInput(_ run: DetectorRun) -> [ReferenceBox] {
        run.detections.map { ReferenceBox($0.inputBox, score: $0.score, label: $0.label) }
    }

    static let k2xl = Case(
        name: "k2xl", fp16: "\(root)/k2xl/K2XL-r768-fp16.mlpackage", fp32: "\(root)/k2xl/K2XL-r768-fp32.mlpackage",
        inputs: "\(root)/k2xl/inputs768", placement: .stretched, resampling: .coreGraphics, padding: 0, threshold: 0,
        reference: { name in
            let pages = try #require((try ReferenceSupport.json("\(root)/k2xl/mac_ref768.json") as? [String: Any])?["pages"] as? [String: Any])
            return try #require(pages[name] as? [[Any]]).compactMap(ReferenceBox.init)
        },
        found: { run, page in normalised(run, page) { $0.score >= KoharuLayoutDecoder.threshold(for: $0.label) } },
        load: { try await KoharuLayoutDetector.load(compiledModel: $0, computeUnits: $1) }
    )

    static let yolo26s = Case(
        name: "yolo26s", fp16: "\(root)/yolo26/YOLO26-fp16.mlpackage", fp32: "\(root)/yolo26/YOLO26-fp32.mlpackage",
        inputs: "\(root)/yolo26/inputs", placement: .centred, resampling: .openCVBilinear, padding: 114, threshold: 0.25,
        reference: { name in
            let rows = try NPZ.floats("o0.npy", in: PrivateFolder.required().url("\(root)/yolo26/ort/\(name).npz"))
            let width = rows.shape[1]
            return (0..<rows.shape[0]).map { row in
                let r = Array(rows.values[(row * width)..<(row * width + 6)]).map(Double.init)
                return ReferenceBox(r[0], r[1], r[2], r[3], score: r[4], label: Int(r[5].rounded()))
            }
        },
        found: { run, _ in inInput(run) },
        load: { try await KoharuYOLODetector.load(compiledModel: $0, computeUnits: $1) }
    )

    static let v4s = Case(
        name: "v4s", fp16: "\(root)/v4s/V4S-fp16.mlpackage", fp32: "\(root)/v4s/V4S-fp32.mlpackage",
        inputs: "\(root)/ogkalu/inputs", placement: .stretched, resampling: .coreGraphics, padding: 0, threshold: 0.3,
        reference: { name in
            let pages = try #require((try ReferenceSupport.json("\(root)/v4s/mac_ref.json") as? [String: Any])?["pages"] as? [String: Any])
            let page = try #require(pages[name] as? [String: Any])
            return try #require(page["ort_float"] as? [[Any]]).compactMap(ReferenceBox.init)
        },
        found: { run, page in normalised(run, page) { _ in true } },
        load: { try await OgkaluDetector.load(compiledModel: $0, computeUnits: $1) },
        // On this Intel Mac's CPU the fp16 package gives a score above the threshold to every
        // query; on its GPU, and on the phone's CPU (the research), it is right.
        fp16Units: .cpuAndGPU
    )

    static let rtmdet2 = Case(
        name: "rtmdet2", fp16: "\(root)/rtmdet/RTMDet2-fp16.mlpackage", fp32: "\(root)/rtmdet/RTMDet2-fp32.mlpackage",
        inputs: "\(root)/rtmdet/inputs", placement: .topLeft, resampling: .coreGraphics, padding: 114, threshold: 0.3,
        reference: { name in
            let pages = try #require((try ReferenceSupport.json("\(root)/rtmdet/mac_ref.json") as? [String: Any])?["pages"] as? [String: Any])
            let page = try #require(pages[name] as? [String: Any])
            return try #require(page["ort"] as? [[Any]]).compactMap(ReferenceBox.init)
        },
        found: { run, _ in inInput(run) },
        load: { try await RTMDetDetector.load(compiledModel: $0, computeUnits: $1) }
    )

    /// The research's own inputs, each fed as the page: the model sees exactly what it saw.
    static func onResearchInputs(_ detector: any RunnableDetector, _ test: Case) async throws -> BoxMatch {
        var total = BoxMatch()
        for name in ReferenceSupport.pageNames {
            let input = try ReferenceSupport.page("\(test.inputs)/\(name).png")
            let run = try await detector.run(input, in: input.fullRect)
            total = total + BoxMatch(reference: try test.reference(name), found: test.found(run, input), threshold: test.threshold)
        }
        return total
    }

    /// The pages themselves, prepared by this code.
    static func onPages(_ detector: any RunnableDetector, _ test: Case) async throws -> (BoxMatch, [Double], [Double]) {
        var total = BoxMatch(), decoding: [Double] = [], network: [Double] = []
        let folder = try PrivateFolder.required()
        for name in ReferenceSupport.pageNames {
            guard let url = try? folder.url("\(ReferenceSupport.pagesFolder)/\(name).png") else { continue }
            let page = try PageBitmap(data: Data(contentsOf: url))
            let run = try await detector.run(page, in: page.fullRect)
            total = total + BoxMatch(reference: try test.reference(name), found: test.found(run, page), threshold: test.threshold)
            decoding.append(ReferenceSupport.ms(run.timings.afterNetwork))
            network.append(ReferenceSupport.ms(run.timings.network))
            #expect(run.blocks.allSatisfy { page.fullRect.cgRect.contains($0.box.insetBy(dx: 0.01, dy: 0.01)) || $0.box.isEmpty })
            for block in run.blocks {
                if let mask = block.balloon?.mask {
                    #expect(mask.rect.clamped(width: page.width, height: page.height) == mask.rect)
                }
            }
        }
        return (total, decoding, network)
    }

    /// The research's input of one page drawn into a model buffer the way the detector draws a
    /// page: unchanged, so the comparison on the research's inputs tests the decoding only.
    static func inputIsDrawnUnchanged(_ test: Case) throws {
        let input = try ReferenceSupport.page("\(test.inputs)/p1.png")
        let buffer = try ModelInputBuffer(width: input.width, height: input.height)
        _ = try buffer.render(input, region: input.fullRect, placement: test.placement, padding: test.padding, resampling: test.resampling)
        let differences = try Self.differences(buffer, input)
        #expect(differences == 0, "\(test.name): \(differences) values differ")
    }

    /// The number of values that differ between a blue-first buffer and a red-first bitmap.
    static func differences(_ buffer: ModelInputBuffer, _ page: PageBitmap) throws -> Int {
        try buffer.withMutableBytes { base, bytesPerRow in
            let bytes = base.assumingMemoryBound(to: UInt8.self)
            var count = 0
            page.pixels.withUnsafeBytes { (pixels: UnsafeRawBufferPointer) in
                for y in 0..<page.height {
                    for x in 0..<page.width {
                        let p = y * page.bytesPerRow + x * 4, b = y * bytesPerRow + x * 4
                        if bytes[b] != pixels[p + 2] { count += 1 }
                        if bytes[b + 1] != pixels[p + 1] { count += 1 }
                        if bytes[b + 2] != pixels[p] { count += 1 }
                    }
                }
            }
            return count
        }
    }

    static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        return sorted.isEmpty ? 0 : sorted[sorted.count / 2]
    }

    static func check(_ test: Case, macRate: Double, fp16InputRate: Double, pageRate: Double) async throws {
        try inputIsDrawnUnchanged(test)
        let fp32 = try await test.load(ReferenceSupport.compiledModel(test.fp32), .cpuOnly)
        let parity = try await onResearchInputs(fp32, test)
        ReferenceSupport.report("\(test.name) fp32, research inputs: \(parity)")
        #expect(parity.share >= macRate, "\(test.name) fp32: \(parity)")

        let fp16 = try await test.load(ReferenceSupport.compiledModel(test.fp16), test.fp16Units)
        let shipped = try await onResearchInputs(fp16, test)
        ReferenceSupport.report("\(test.name) fp16, research inputs: \(shipped)")
        #expect(shipped.share >= fp16InputRate, "\(test.name) fp16: \(shipped)")

        let (pages, decoding, network) = try await onPages(fp16, test)
        ReferenceSupport.report("\(test.name) fp16, pages prepared here: \(pages)")
        ReferenceSupport.report(String(
            format: "%@ fp16 on %d pages, debug build, wall clock: output to blocks median %.2f ms, max %.2f ms; network median %.0f ms",
            test.name, decoding.count, median(decoding), decoding.max() ?? 0, median(network)
        ))
        #expect(pages.share >= pageRate, "\(test.name) pages: \(pages)")
    }

    // The floors are what this code measured on 2026-11-15 and again on 2026-11-19 (the runs are
    // deterministic on this Mac). The fp32 rates equal the research's Swift code on its own inputs;
    // the fp16 rates are above the phone's (2XL 90.4% and 77.3%, YOLO26s 98%, v4-s 98.9% and 95.3%,
    // RTMDet2 91.2%).

    @Test func koharuLayout2XL() async throws {
        try await Self.check(Self.k2xl, macRate: 1, fp16InputRate: 0.954, pageRate: 0.81) // 605/634, 469/579
    }

    @Test func koharuYOLO26s() async throws {
        try await Self.check(Self.yolo26s, macRate: 1, fp16InputRate: 1, pageRate: 1)
    }

    @Test func ogkaluV4S() async throws {
        try await Self.check(Self.v4s, macRate: 1, fp16InputRate: 0.992, pageRate: 0.967) // 260/262, 211/218
    }

    @Test func rtmDet2() async throws {
        try await Self.check(Self.rtmdet2, macRate: 1, fp16InputRate: 0.994, pageRate: 0.974) // 669/673, 570/585
    }

    /// The OpenCV-compatible letterbox of each page equals the research's, made with OpenCV.
    @Test func theYOLOLetterboxEqualsOpenCVs() throws {
        let folder = try PrivateFolder.required()
        var pages = 0, differing = 0
        for name in ReferenceSupport.pageNames {
            guard let url = try? folder.url("\(ReferenceSupport.pagesFolder)/\(name).png") else { continue }
            let page = try PageBitmap(data: Data(contentsOf: url))
            let buffer = try ModelInputBuffer(side: 1024)
            _ = try buffer.render(page, region: page.fullRect, placement: .centred, padding: 114, resampling: .openCVBilinear)
            let research = try ReferenceSupport.page("\(Self.root)/yolo26/inputs/\(name).png")
            let count = try Self.differences(buffer, research)
            if count > 0 { differing += 1 }
            pages += 1
            #expect(count == 0, "\(name): \(count) values differ")
        }
        ReferenceSupport.report("yolo26s letterbox: \(pages - differing) of \(pages) pages equal OpenCV's value for value")
        #expect(pages == 17)
    }
}
