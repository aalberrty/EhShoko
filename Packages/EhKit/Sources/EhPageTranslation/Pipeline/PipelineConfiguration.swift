import CoreML
import EhModels
import Foundation

/// Where the installed files of a model set are and what each model runs on: everything
/// `PagePipeline.load(_:)` needs.
public struct PipelineConfiguration: Sendable, Equatable {
    public var modelSet: PageTranslationModelSet
    /// The detector's compiled model (`.mlmodelc`).
    public var detector: URL
    public var reader: ReaderFiles
    /// The translator's installed files: the release's folder for the Core ML translator, the
    /// one model file for a language model.
    public var translator: URL
    /// `nil` runs a model where the research measured it best on the phone.
    public var detectorUnits: MLComputeUnits?
    public var readerUnits: MLComputeUnits?
    public var translatorUnits: MLComputeUnits?

    public enum ReaderFiles: Sendable, Equatable {
        /// The compiled encoder and decoder and `vocab.txt`.
        case cpt2(encoder: URL, decoder: URL, vocabulary: URL)
        /// The compiled model and `nar_vocabulary_6817.json`.
        case narSmall(model: URL, vocabulary: URL)

        public var choice: TextReaderChoice {
            switch self {
            case .cpt2: .cpt2
            case .narSmall: .narSmall
            }
        }
    }

    public init(
        modelSet: PageTranslationModelSet, detector: URL, reader: ReaderFiles, translator: URL,
        detectorUnits: MLComputeUnits? = nil, readerUnits: MLComputeUnits? = nil,
        translatorUnits: MLComputeUnits? = nil
    ) {
        self.modelSet = modelSet
        self.detector = detector
        self.reader = reader
        self.translator = translator
        self.detectorUnits = detectorUnits
        self.readerUnits = readerUnits
        self.translatorUnits = translatorUnits
    }
}

/// How long each model of a pipeline took to load.
public struct PipelineLoadTimings: Sendable, Equatable {
    public var detector: Duration = .zero
    public var reader: Duration = .zero
    public var translator: Duration = .zero

    public init() {}

    public var total: Duration { detector + reader + translator }
}

public enum PipelineConfigurationError: Error, Equatable {
    /// The reader's files are not those of the model set's reader.
    case readerMismatch(expected: TextReaderChoice, files: TextReaderChoice)
}

extension PagePipeline {
    /// Loads the detector, the reader and the translator of `configuration`, one after the
    /// other, which is how their loading times were measured.
    ///
    /// The first load of a Core ML model builds its program for the Neural Engine and takes
    /// seconds (9.4, 6.7 and about 9 on the phone); later loads take tenths of a second. The
    /// Core ML translator comes back once its shortest input length and its decoder are loaded
    /// and loads the longer lengths behind. A language model is loaded through
    /// `languageModel`; without one such a choice throws `PageTranslatorError.unavailable`.
    public static func load(
        _ configuration: PipelineConfiguration, languageModel: PageTranslatorLoader.LanguageModelLoader? = nil,
        rules: PipelineRules = PipelineRules()
    ) async throws -> PagePipeline {
        let set = configuration.modelSet
        guard configuration.reader.choice == set.reader else {
            throw PipelineConfigurationError.readerMismatch(expected: set.reader, files: configuration.reader.choice)
        }
        let clock = ContinuousClock()
        var timings = PipelineLoadTimings()

        var start = clock.now
        let detector = try await TextDetectors.load(
            set.detector, compiledModel: configuration.detector, computeUnits: configuration.detectorUnits
        )
        timings.detector = clock.now - start

        try Task.checkCancellation()
        start = clock.now
        let readerUnits = configuration.readerUnits ?? TextReaders.preferredComputeUnits(for: set.reader)
        let reader: any TextReader
        switch configuration.reader {
        case let .cpt2(encoder, decoder, vocabulary):
            reader = try await CPTReader.load(
                encoder: encoder, decoder: decoder, vocabulary: vocabulary, computeUnits: readerUnits
            )
        case let .narSmall(model, vocabulary):
            reader = try await NARReader.load(compiledModel: model, vocabulary: vocabulary, computeUnits: readerUnits)
        }
        timings.reader = clock.now - start

        try Task.checkCancellation()
        start = clock.now
        var loader = PageTranslatorLoader(languageModel: languageModel)
        if let units = configuration.translatorUnits { loader.computeUnits = units }
        let translator = try await loader.load(set.translator, from: configuration.translator)
        timings.translator = clock.now - start

        var pipeline = PagePipeline(detector: detector, reader: reader, translator: translator, rules: rules)
        pipeline.loadTimings = timings
        return pipeline
    }
}
