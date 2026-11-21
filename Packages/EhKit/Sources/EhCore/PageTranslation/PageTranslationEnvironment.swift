import CoreML
import EhModels
import EhPageTranslation
import Foundation

/// What pages are translated with at a given moment: the models of the current choices and
/// where their installed files are. The service reads it each time a reader acts, so a
/// changed choice is noticed and never mixes with work made under the old one.
public struct PageTranslationSetup: Sendable, Equatable {
    public var modelSet: PageTranslationModelSet
    /// The repaint choice pages are drawn with: the chosen one while its model is installed,
    /// `.off` otherwise, so a patch file's folder always names what it was drawn with.
    public var repaint: RepaintChoice
    /// The installed files of the set's three models; `nil` while one of them is not
    /// installed. Stored pages are shown either way.
    public var pipeline: PipelineConfiguration?
    /// The repaint model's compiled file; `nil` when `repaint` is `.off`.
    public var repaintModel: URL?
    public var repaintUnits: MLComputeUnits
    /// The artifacts the setup loads, so they can be let go before their files are deleted.
    public var artifacts: Set<ModelArtifactID>

    public init(
        modelSet: PageTranslationModelSet, repaint: RepaintChoice, pipeline: PipelineConfiguration?,
        repaintModel: URL? = nil, repaintUnits: MLComputeUnits = .cpuAndGPU, artifacts: Set<ModelArtifactID> = []
    ) {
        self.modelSet = modelSet
        self.repaint = repaint
        self.pipeline = pipeline
        self.repaintModel = repaintModel
        self.repaintUnits = repaintUnits
        self.artifacts = artifacts
    }

    /// Names the patch files drawn under this setup.
    public var variant: PageTranslationPatchVariant {
        PageTranslationPatchVariant(modelSet: modelSet, repaint: repaint, renderVersion: PageRenderer.renderVersion)
    }

    /// Names the patch file of a page whose text on artwork was filled although a repaint
    /// model is chosen (the model failed): it is not kept as that model's drawing, so the
    /// page is drawn again the next time it is wanted.
    var filledVariant: PageTranslationPatchVariant {
        PageTranslationPatchVariant(modelSet: modelSet, repaint: .off, renderVersion: PageRenderer.renderVersion)
    }
}

/// What the service is built from. The app's values are `PageTranslationEnvironment.live`;
/// tests give stub stages, injected states and a temporary cache.
public struct PageTranslationEnvironment: Sendable {
    /// Runs once, the first time the service is used in a process and never at launch: the
    /// model store looks at its folder.
    public var prepare: @Sendable () async -> Void
    /// What to translate with now; `nil` while a kind has no model this user can have.
    public var setup: @Sendable () async -> PageTranslationSetup?
    /// A page's original bytes.
    public var imageData: @Sendable (URL) async throws -> Data
    /// Stage 0: a page's bytes into its working bitmap. Throws `PageBitmapError`.
    public var decode: @Sendable (Data) async throws -> PageBitmap
    /// Loads the detector, the reader and the translator: stages 1 to 4.
    public var loadPipeline: @Sendable (PipelineConfiguration) async throws -> PagePipeline
    /// Loads the repaint model from its compiled file.
    public var loadInpainter: @Sendable (URL, MLComputeUnits) async throws -> any Inpainter
    /// Stages 5 and 6: a page's stored text into patches.
    public var draw: @Sendable (PageTranslation, PageBitmap, (any Inpainter)?) async throws -> PageDrawing
    public var writer: PageTranslationResultWriter
    public var patchStore: PageTranslationPatchStore
    public var heat: @Sendable () -> PageTranslationHeat
    public var isLowPowerModeEnabled: @Sendable () -> Bool
    public var now: @Sendable () -> Date
    public var logger: AppLogger

    /// A stage that is not given is the real one: the decoder, the repaint model on Core ML,
    /// the renderer, the phone's own states.
    ///
    /// The real stages are set in the body, not written as default arguments. A closure that
    /// is a default argument here and awaits a stage was miscompiled by Swift 6.2.3: the
    /// decoder's came back with the wrong result, or crashed in the task's own memory, while
    /// the same closure written anywhere else was sound. `PageTranslationEnvironmentTests`
    /// runs each of them.
    public init(
        prepare: (@Sendable () async -> Void)? = nil,
        setup: @escaping @Sendable () async -> PageTranslationSetup?,
        imageData: @escaping @Sendable (URL) async throws -> Data,
        decode: (@Sendable (Data) async throws -> PageBitmap)? = nil,
        loadPipeline: @escaping @Sendable (PipelineConfiguration) async throws -> PagePipeline,
        loadInpainter: (@Sendable (URL, MLComputeUnits) async throws -> any Inpainter)? = nil,
        draw: (@Sendable (PageTranslation, PageBitmap, (any Inpainter)?) async throws -> PageDrawing)? = nil,
        writer: PageTranslationResultWriter,
        patchStore: PageTranslationPatchStore,
        heat: (@Sendable () -> PageTranslationHeat)? = nil,
        isLowPowerModeEnabled: (@Sendable () -> Bool)? = nil,
        now: (@Sendable () -> Date)? = nil,
        logger: AppLogger
    ) {
        self.prepare = prepare ?? Self.nothingToPrepare
        self.setup = setup
        self.imageData = imageData
        self.decode = decode ?? Self.decodePage
        self.loadPipeline = loadPipeline
        self.loadInpainter = loadInpainter ?? Self.loadRepaintModel
        self.draw = draw ?? Self.drawPage
        self.writer = writer
        self.patchStore = patchStore
        self.heat = heat ?? Self.systemHeat
        self.isLowPowerModeEnabled = isLowPowerModeEnabled ?? Self.systemLowPowerMode
        self.now = now ?? Self.systemNow
        self.logger = logger
    }

    // The real stages, as functions with names.

    static func nothingToPrepare() async {}

    /// Decodes on the global executor: the decoder's own entry does that.
    static func decodePage(_ data: Data) async throws -> PageBitmap {
        try await PageBitmap.decode(data)
    }

    static func loadRepaintModel(_ compiledModel: URL, _ computeUnits: MLComputeUnits) async throws -> any Inpainter {
        try await LamaInpainter(compiledModel: compiledModel, computeUnits: computeUnits)
    }

    static func drawPage(
        _ translation: PageTranslation, _ page: PageBitmap, _ inpainter: (any Inpainter)?
    ) async throws -> PageDrawing {
        try await PageDrawer.draw(translation, on: page, inpainter: inpainter)
    }

    static func systemHeat() -> PageTranslationHeat {
        PageTranslationHeat(ProcessInfo.processInfo.thermalState)
    }

    static func systemLowPowerMode() -> Bool {
        ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    static func systemNow() -> Date { .now }
}

// MARK: - The installed files of a setup

extension PageTranslationSetup {
    /// The setup of a model set and a repaint choice, from where the model store installed
    /// their artifacts. `files` gives an installed artifact's files, or `nil`.
    ///
    /// The file names are those of the catalog: a Core ML artifact with one package (the
    /// detectors, the repaint models) is that package compiled; the readers and the Core ML
    /// translator name theirs below.
    public static func resolve(
        modelSet: PageTranslationModelSet, repaint: RepaintChoice,
        files: (ModelArtifactID) -> InstalledModelFiles?
    ) -> PageTranslationSetup {
        var artifacts = Set<ModelArtifactID>()
        var pipeline: PipelineConfiguration?
        if let detector = files(modelSet.detector.artifact), let detectorModel = detector.onlyCompiledModel,
           let reader = files(modelSet.reader.artifact), let translator = files(modelSet.translator.artifact),
           let translatorLocation = translatorLocation(modelSet.translator, in: translator) {
            pipeline = PipelineConfiguration(
                modelSet: modelSet, detector: detectorModel, reader: readerFiles(modelSet.reader, in: reader),
                translator: translatorLocation, detectorUnits: detector.computeUnits,
                readerUnits: reader.computeUnits, translatorUnits: translator.computeUnits
            )
            artifacts.formUnion(modelSet.artifacts)
        }
        var drawnWith = RepaintChoice.off
        var repaintModel: URL?
        var repaintUnits = MLComputeUnits.cpuAndGPU
        if let artifact = repaint.artifact, let installed = files(artifact), let model = installed.onlyCompiledModel {
            drawnWith = repaint
            repaintModel = model
            // Never the Neural Engine for the repaint model: it returns black or noisy tiles.
            if let units = installed.computeUnits, units != .cpuAndNeuralEngine, units != .all { repaintUnits = units }
            artifacts.insert(artifact)
        }
        return PageTranslationSetup(
            modelSet: modelSet, repaint: drawnWith, pipeline: pipeline, repaintModel: repaintModel,
            repaintUnits: repaintUnits, artifacts: artifacts
        )
    }

    static let cptEncoderPackage = "CPTEncoder-fp16.mlpackage"
    static let cptDecoderPackage = "CPTDecoder-fp16.mlpackage"
    static let cptVocabulary = "vocab.txt"
    static let narPackage = "coreml/mangaocr_nar_small_fp16.mlpackage"
    static let narVocabulary = "nar_vocabulary_6817.json"

    static func readerFiles(_ choice: TextReaderChoice, in installed: InstalledModelFiles) -> PipelineConfiguration.ReaderFiles {
        switch choice {
        case .cpt2:
            .cpt2(
                encoder: installed.compiledModel(ofPackage: cptEncoderPackage),
                decoder: installed.compiledModel(ofPackage: cptDecoderPackage), vocabulary: installed.file(cptVocabulary)
            )
        case .narSmall:
            .narSmall(model: installed.compiledModel(ofPackage: narPackage), vocabulary: installed.file(narVocabulary))
        }
    }

    /// The Core ML translator keeps its author's folder; a language model is one file.
    static func translatorLocation(_ choice: TranslatorChoice, in installed: InstalledModelFiles) -> URL? {
        switch choice.engine {
        case .coreML:
            return installed.folder
        case .languageModel:
            let models = installed.artifact.files.filter { $0.path.hasSuffix(".gguf") }
            guard models.count == 1 else { return nil }
            return installed.file(models[0].path)
        }
    }
}

extension InstalledModelFiles {
    /// The compiled model of an artifact that has exactly one package.
    var onlyCompiledModel: URL? {
        let packages = artifact.packages
        guard packages.count == 1 else { return nil }
        return compiledModel(ofPackage: packages[0])
    }

    /// The compute units the catalog says the artifact was measured with.
    var computeUnits: MLComputeUnits? {
        guard case .coreML(let units) = artifact.loading else { return nil }
        return switch units {
        case .cpuOnly: .cpuOnly
        case .cpuAndGPU: .cpuAndGPU
        case .cpuAndNeuralEngine: .cpuAndNeuralEngine
        case .all: .all
        }
    }
}
