import CoreML
import Dependencies
import EhModels
import EhPageTranslation
import Foundation
import Testing
@testable import EhCore

/// Where a setup finds the installed files of the catalog's artifacts.
@Suite struct PageTranslationSetupTests {
    static let root = URL(fileURLWithPath: "/models", isDirectory: true)
    static let all = Set(ModelCatalog.generated.artifacts.map(\.id))

    static func files(_ installed: Set<ModelArtifactID>, catalog: ModelCatalog = .generated) -> (ModelArtifactID) -> InstalledModelFiles? {
        { id in
            guard installed.contains(id), let artifact = catalog.artifact(id) else { return nil }
            return InstalledModelFiles(
                artifact: artifact, folder: root.appending(path: id.rawValue, directoryHint: .isDirectory), isPrepared: true
            )
        }
    }

    static func path(_ url: URL?) -> String? { url?.path(percentEncoded: false) }

    @Test func theDefaultSetsFiles() throws {
        let setup = PageTranslationSetup.resolve(modelSet: .default, repaint: .lamaManga, files: Self.files(Self.all))
        let pipeline = try #require(setup.pipeline)

        #expect(Self.path(pipeline.detector) == "/models/det-k2xl-768/K2XL-r768-fp16.mlmodelc/")
        guard case let .cpt2(encoder, decoder, vocabulary) = pipeline.reader else {
            Issue.record("the default reader is CPT v2")
            return
        }
        #expect(Self.path(encoder) == "/models/ocr-cpt2/CPTEncoder-fp16.mlmodelc/")
        #expect(Self.path(decoder) == "/models/ocr-cpt2/CPTDecoder-fp16.mlmodelc/")
        #expect(Self.path(vocabulary) == "/models/ocr-cpt2/vocab.txt")
        // The Core ML translator keeps its author's folder.
        #expect(Self.path(pipeline.translator) == "/models/mt-jmt-fast-1/")
        #expect(JMTFiles(root: pipeline.translator).tokenizer.path == "/models/mt-jmt-fast-1/tokenizer/tokenizer.json")
        #expect(pipeline.detectorUnits == .cpuAndNeuralEngine && pipeline.readerUnits == .cpuAndNeuralEngine)
        #expect(pipeline.translatorUnits == .cpuAndNeuralEngine)

        #expect(setup.repaint == .lamaManga && setup.repaintUnits == .cpuAndGPU)
        #expect(Self.path(setup.repaintModel) == "/models/inp-lama-manga/LaMa-fp16.mlmodelc/")
        #expect(setup.artifacts == [.k2xl, .cpt2, .jmtFast1, .lamaManga])
        #expect(setup.variant.folderName == "k2xl768.cpt2.jmt1.t1.lamamanga.r\(PageRenderer.renderVersion)")
    }

    @Test func theOtherChoicesFiles() throws {
        let set = PageTranslationModelSet(detector: .v4s, reader: .narSmall)
        let setup = PageTranslationSetup.resolve(modelSet: set, repaint: .bigLama, files: Self.files(Self.all))
        let pipeline = try #require(setup.pipeline)

        #expect(Self.path(pipeline.detector) == "/models/det-v4s/V4S-fp16.mlmodelc/")
        // No operation of ogkalu v4-s runs on the Neural Engine.
        #expect(pipeline.detectorUnits == .cpuOnly)
        #expect(pipeline.reader == .narSmall(
            model: Self.root.appending(path: "ocr-nar-small/coreml/mangaocr_nar_small_fp16.mlmodelc", directoryHint: .isDirectory),
            vocabulary: Self.root.appending(path: "ocr-nar-small/nar_vocabulary_6817.json", directoryHint: .notDirectory)
        ))
        #expect(Self.path(setup.repaintModel) == "/models/inp-big-lama/BigLaMa-fp32.mlmodelc/")
        for detector in TextDetectorChoice.allCases {
            let resolved = PageTranslationSetup.resolve(
                modelSet: PageTranslationModelSet(detector: detector), repaint: .off, files: Self.files(Self.all)
            )
            #expect(resolved.pipeline?.detector.pathExtension == "mlmodelc")
            #expect(resolved.repaint == .off && resolved.repaintModel == nil)
        }
    }

    @Test func aSetWithAModelMissingHasNoPipelineAndStillNamesItsCache() {
        for missing in [ModelArtifactID.k2xl, .cpt2, .jmtFast1] {
            let setup = PageTranslationSetup.resolve(
                modelSet: .default, repaint: .lamaManga, files: Self.files(Self.all.subtracting([missing]))
            )
            #expect(setup.pipeline == nil)
            #expect(setup.modelSet == .default && setup.artifacts == [.lamaManga])
        }
    }

    @Test func aRepaintModelThatIsNotInstalledMeansPagesAreFilled() {
        let setup = PageTranslationSetup.resolve(
            modelSet: .default, repaint: .lamaManga, files: Self.files(Self.all.subtracting([.lamaManga]))
        )
        // The patch files say what they were drawn with, not what was chosen.
        #expect(setup.repaint == .off && setup.repaintModel == nil)
        #expect(setup.variant.folderName.hasSuffix(".fill.r\(PageRenderer.renderVersion)"))
        #expect(setup.pipeline != nil && setup.artifacts == [.k2xl, .cpt2, .jmtFast1])
    }

    /// The names the code reads are the catalog's: a renamed package would show here, not
    /// on the phone.
    @Test func theFilesTheCodeNamesAreInTheCatalog() throws {
        let catalog = ModelCatalog.generated
        let cpt = try #require(catalog.artifact(.cpt2)), nar = try #require(catalog.artifact(.narSmall))
        #expect(Set(cpt.packages) == [PageTranslationSetup.cptEncoderPackage, PageTranslationSetup.cptDecoderPackage])
        #expect(cpt.files.contains { $0.path == PageTranslationSetup.cptVocabulary })
        #expect(nar.packages == [PageTranslationSetup.narPackage])
        #expect(nar.files.contains { $0.path == PageTranslationSetup.narVocabulary })
        for id in [ModelArtifactID.k2xl, .yolo26s, .v4s, .rtmdet2, .lamaManga, .bigLama] {
            #expect(catalog.artifact(id)?.packages.count == 1, "\(id) is one package")
        }
        // The translator's own layout, compiled in place.
        let jmt = try #require(catalog.artifact(.jmtFast1))
        let files = JMTFiles(root: Self.root)
        for (compiled, package) in [(files.encoder, "coreml/encoder_static_fp16.mlpackage"), (files.decoder, "coreml/decoder_fp16.mlpackage")] {
            #expect(jmt.packages.contains(package))
            #expect(compiled.path == Self.root.appending(path: ModelStoreLayout.compiledPath(ofPackage: package)).path)
        }
        for file in [files.config, files.host, files.tokenizer] {
            let relative = String(file.path.dropFirst(Self.root.path.count + 1))
            #expect(jmt.files.contains { $0.path == relative }, "\(relative)")
        }
    }

    @Test func aLanguageModelIsItsOneFile() throws {
        let credit = try #require(ModelCatalog.generated.artifacts.first?.credit)
        let artifact = ModelArtifact(
            id: .hyMT2, version: "1", role: .translator, sharing: .fromPublisher, credit: credit,
            loading: .languageModel(promptFamily: "hymt2"),
            files: [ModelFile("Hy-MT2-1.8B-Q4_K_M.gguf", 1, "00"), ModelFile("LICENSE", 1, "00")]
        )
        var catalog = ModelCatalog.generated
        catalog.artifacts.append(artifact)
        let set = PageTranslationModelSet(translator: .hyMT2)

        let setup = PageTranslationSetup.resolve(
            modelSet: set, repaint: .off, files: Self.files(Self.all.union([.hyMT2]), catalog: catalog)
        )

        #expect(Self.path(setup.pipeline?.translator) == "/models/mt-hy-mt2-1.8b/Hy-MT2-1.8B-Q4_K_M.gguf")
        // Neither compiled nor on Core ML.
        #expect(setup.pipeline?.translatorUnits == nil)
    }
}

@Suite struct PageTranslationClientTests {
    @Test func aPlaceholderSessionEndsAtOnce() async {
        let session = PageTranslationSession.ended
        session.setWindow(.empty)
        session.retry(1)
        session.close()
        var events = 0
        for await _ in session.events { events += 1 }
        #expect(events == 0)
    }

    @Test func aTestThatDoesNotInstallAClientIsToldSo() {
        withKnownIssue {
            @Dependency(\.pageTranslation) var pageTranslation
            _ = pageTranslation.openSession("1")
        }
    }
}
