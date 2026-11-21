import EhLlama
import EhPageTranslation
import Foundation

// The models of a setup: loading them, why that failed, and letting them go.

extension PageTranslationService {
    /// Why a setup's models did not load.
    ///
    /// A reader is told one thing for all of them, `PageTranslationFailure.modelsFailedToLoad`,
    /// and offers Retry. The service keeps the reason: it is what the log says, and what a
    /// rule for a language model that does not fit has to go by.
    enum LoadFailure: Sendable, Equatable {
        /// The language model's file is not where the model store said it is.
        case languageModelMissing
        /// llama.cpp could not read the file as a model.
        case languageModelUnreadable
        /// The language model was read, and the memory it generates in could not be had. Kept
        /// apart from every other reason: its weights are mapped from the file and cost the
        /// app nothing, so this is the moment a model that is too large for the phone, or
        /// for the phone with the repaint model beside it, shows.
        case languageModelOutOfMemory
        /// This build has no engine for language models.
        case languageModelUnavailable
        /// Anything else: a Core ML model that did not load, files that do not belong together.
        case other

        init(_ error: any Error) {
            switch error {
            case LlamaError.modelNotFound: self = .languageModelMissing
            case LlamaError.loadFailed: self = .languageModelUnreadable
            case LlamaError.contextFailed: self = .languageModelOutOfMemory
            case PageTranslatorError.unavailable: self = .languageModelUnavailable
            default: self = .other
            }
        }

        /// The line the log gets.
        var summary: String {
            switch self {
            case .languageModelMissing: "the language model's file is missing"
            case .languageModelUnreadable: "the language model's file could not be read as a model"
            case .languageModelOutOfMemory: "no memory for the language model to generate in"
            case .languageModelUnavailable: "this build runs no language model"
            case .other: "a model did not load"
            }
        }
    }

    /// Why the models did not load, while that is so: until a retry or a changed setup.
    var loadFailure: LoadFailure? {
        if case let .failed(failure) = pipelineState { return failure }
        return nil
    }

    // MARK: Loading and letting go

    /// Loads the setup's detector, reader and translator, when the first page needs text and
    /// not before. A language model is the last of the three: its file is mapped, and the
    /// first one of a process also starts llama.cpp.
    func startLoadingPipeline(_ configuration: PipelineConfiguration) {
        generation += 1
        let loadGeneration = generation
        let interval = PerformanceSignposts.begin(.pageTranslateLoad, configuration.modelSet.key)
        let start = clock.now
        let task = Task(priority: .utility) { [environment, clock] in
            let result: Result<PagePipeline, any Error>
            do {
                result = .success(try await environment.loadPipeline(configuration))
            } catch {
                result = .failure(error)
            }
            self.pipelineLoaded(loadGeneration, result, interval: interval, took: clock.now - start)
        }
        pipelineState = .loading(task, generation: loadGeneration)
    }

    private func pipelineLoaded(
        _ loadGeneration: Int, _ result: Result<PagePipeline, any Error>, interval: PerformanceInterval, took: Duration
    ) {
        guard case .loading(_, loadGeneration) = pipelineState else {
            interval.end("cancelled")
            return
        }
        switch result {
        case let .success(pipeline):
            pipelineState = .ready(pipeline)
            interval.end("done")
            // No longer "getting ready": the pages that waited for the models wait for their turn.
            for key in pagesWaitingForText() { emit(key, .translating) }
            let translator = pipeline.loadTimings.translator.formatted(Self.seconds)
            environment.logger.info(
                "Page translation models loaded in \(took.formatted(Self.seconds)), the translator in \(translator).",
                category: Self.logCategory
            )
        case let .failure(error) where error is CancellationError:
            pipelineState = .unloaded
            interval.end("cancelled")
        case let .failure(error):
            let failure = LoadFailure(error)
            pipelineState = .failed(failure)
            interval.end("failed")
            environment.logger.error(
                "Page translation models did not load, \(failure.summary): \(error)", category: Self.logCategory
            )
        }
        pump()
    }

    /// Lets go of the loaded detector, reader and translator, or of their loading.
    ///
    /// Whoever calls this has cancelled the pages in work, and a language model ends its
    /// answer within one token of that. `stop()` says it once more to the model itself, for
    /// an answer that runs in a task the service does not own: the model's gigabytes are
    /// freed only when nothing generates with it any more.
    func releasePipeline() {
        switch pipelineState {
        case let .loading(task, _):
            task.cancel()
        case let .ready(pipeline):
            (pipeline.translator as? LanguageModelTranslator)?.stop()
        case .unloaded, .failed:
            break
        }
        pipelineState = .unloaded
    }
}
