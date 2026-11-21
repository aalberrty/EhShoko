import EhLlama
import EhModels
import EhPageTranslation
import Foundation
import Testing
@testable import EhCore

/// The service with a language model as the translator: the real service, the real
/// `LanguageModelTranslator`, and a stub model under it that answers at once or waits until
/// it is told.
@Suite struct PageTranslationServiceLanguageModelTests {
    static let modelSet = PageTranslationModelSet(translator: .hyMT2)

    /// A world whose translator is Hy-MT2 on a stub model, and that model's ledger.
    static func world() async throws -> (TranslationWorld, LanguageModelLedger) {
        let world = try await TranslationWorld(setup: TranslationWorld.setup(modelSet))
        let ledger = LanguageModelLedger()
        world.set { $0.languageModels = ledger }
        return (world, ledger)
    }

    static func texts(_ world: TranslationWorld) -> [String] { world.log.filter { $0.hasPrefix("text") } }

    static func hasFailed(_ events: SessionEvents, _ page: Int) -> Bool {
        events.statuses(of: page).contains { status in
            if case .failed = status { return true }
            return false
        }
    }

    // MARK: A page

    @Test func aPageGoesToTheModelAsNumberedLinesAndIsStoredAndDrawn() async throws {
        let (world, ledger) = try await Self.world()
        let service = world.service()
        let session = await service.open()

        await service.show(session, onScreen: [1])
        try await eventually("page 1 to be translated") { session.events.isTranslated(1) }

        // The model's own prompt, with the page's one line, and an answer sized for it.
        #expect(ledger.prompts == [LanguageModelPrompt.hymt2.text(for: ["こんにちは"])])
        #expect(ledger.maxTokens == [LanguageModelProfile.answerLimit(sourceTokens: "1: こんにちは".count)])
        let stored = try await world.storedText(of: 1, modelSet: Self.modelSet)
        #expect(stored?.regions.first?.translation == "你好")
        #expect(world.hasPatchFile(of: 1))
        #expect(session.events.statuses(of: 1).dropLast() == [.loadingModels, .translating])
    }

    // MARK: Loading

    @Test func theModelIsLoadedWhenTheFirstPageNeedsItAndOnceForAllPages() async throws {
        let (world, ledger) = try await Self.world()
        let service = world.service()
        let session = await service.open()
        #expect(ledger.loaded == 0 && world.pipelineLoads.isEmpty)

        await service.show(session, onScreen: [1])
        try await eventually("page 1 to be translated") { session.events.isTranslated(1) }
        await service.show(session, onScreen: [2], behind: [1])
        try await eventually("page 2 to be translated") { session.events.isTranslated(2) }

        #expect(ledger.loaded == 1 && ledger.alive == 1)
        #expect(world.pipelineLoads.map(\.modelSet) == [Self.modelSet])
    }

    static let loadFailures: [(any Error, PageTranslationService.LoadFailure)] = [
        (LlamaError.contextFailed, .languageModelOutOfMemory),
        (LlamaError.modelNotFound("/models/model.gguf"), .languageModelMissing),
        (LlamaError.loadFailed("/models/model.gguf"), .languageModelUnreadable),
        (PageTranslatorError.unavailable(.hyMT2), .languageModelUnavailable),
        (ModelSignatureError.noImageInput, .other)
    ]

    /// The reader is told one thing whatever the reason; the service keeps the reason.
    @Test(arguments: loadFailures)
    func aModelThatDoesNotLoadFailsItsPagesAndTheReasonIsKept(
        error: any Error, failure: PageTranslationService.LoadFailure
    ) async throws {
        let (world, ledger) = try await Self.world()
        world.set { $0.modelLoadError = error }
        let service = world.service()
        let session = await service.open()

        await service.show(session, onScreen: [1], ahead: [2])
        try await eventually("both pages to fail") {
            [1, 2].allSatisfy { session.events.status(of: $0) == .failed(.modelsFailedToLoad) }
        }
        #expect(await service.loadFailure == failure)
        #expect(ledger.loaded == 0 && ledger.prompts.isEmpty)

        // Retry loads again, and the reason goes with the failure.
        world.set { $0.modelLoadError = nil }
        await service.perform(.retry(session.id, pageIndex: 1))
        try await eventually("both pages to be translated") { [1, 2].allSatisfy(session.events.isTranslated) }
        #expect(await service.loadFailure == nil)
        #expect(world.pipelineLoads.count == 2 && ledger.loaded == 1)
    }

    @Test func noMemoryForALanguageModelIsToldApartFromEveryOtherReason() {
        typealias Failure = PageTranslationService.LoadFailure
        #expect(Failure(LlamaError.contextFailed) == .languageModelOutOfMemory)
        let others: [any Error] = [
            LlamaError.modelNotFound("a"), LlamaError.loadFailed("a"), LlamaError.unloaded, LlamaError.decodeFailed(1),
            PageTranslatorError.unavailable(.qwen35_4B), CancellationError(), ModelSignatureError.noImageInput
        ]
        #expect(others.allSatisfy { Failure($0) != .languageModelOutOfMemory })
        #expect(Failure(LlamaError.unloaded) == .other && Failure(LlamaError.decodeFailed(1)) == .other)
        #expect(Set([Failure.languageModelMissing, .languageModelUnreadable, .languageModelOutOfMemory,
                     .languageModelUnavailable, .other].map(\.summary)).count == 5)
    }

    /// The app's service loads a language model through llama.cpp: a file that is not there
    /// is llama's own error, not "this build runs no language model".
    @Test func theAppsServiceLoadsLanguageModelsThroughLlama() async throws {
        LlamaTestEnvironment.keepMetalOff()
        let load = try #require(PageTranslationService.languageModelLoader)
        let file = URL.temporaryDirectory.appending(path: "no-model-\(UUID().uuidString).gguf")
        await #expect(throws: LlamaError.modelNotFound(file.path)) {
            _ = try await load(.galTransl4B, file)
        }
    }

    // MARK: How far ahead

    /// On screen, one page ahead, then the page before; nothing further ahead.
    @Test func onePageAheadThenThePageBefore() async throws {
        let (world, ledger) = try await Self.world()
        let service = world.service()
        let session = await service.open()

        await service.show(session, onScreen: [5], ahead: [6, 7, 8], behind: [4])
        try await eventually("the pages to be translated") { [4, 5, 6].allSatisfy(session.events.isTranslated) }
        try await settled(service)

        #expect(Self.texts(world) == ["text 5", "text 6", "text 4"])
        #expect(ledger.prompts.count == 3)
        #expect(session.events.status(of: 7) == .translating && session.events.status(of: 8) == .translating)
    }

    @Test func atSeriousHeatOnlyThePageOnScreenGoesToTheModel() async throws {
        let (world, ledger) = try await Self.world()
        world.set { $0.heat = .serious }
        let service = world.service()
        let session = await service.open()

        await service.show(session, onScreen: [5], ahead: [6], behind: [4])
        try await eventually("page 5 to be translated") { session.events.isTranslated(5) }
        try await settled(service)

        #expect(Self.texts(world) == ["text 5"] && ledger.prompts.count == 1)
    }

    /// The page ahead that the model is writing when the phone turns hot is finished: its
    /// tokens are spent, and it is the page the reader comes to next. Its text is kept, and
    /// it is drawn when it comes on screen. Nothing else is begun.
    @Test func thePageAheadInWorkWhenThePhoneTurnsHotIsFinishedAndNoOtherIsBegun() async throws {
        let (world, ledger) = try await Self.world()
        let service = world.service()
        let session = await service.open()
        ledger.hold(call: 2)

        await service.show(session, onScreen: [5], ahead: [6, 7], behind: [4])
        try await eventually("page 6 to be with the model") { ledger.prompts.count == 2 && ledger.generating == 1 }
        world.set { $0.heat = .serious }
        ledger.release()
        try await eventually("page 6's text to be kept") {
            (try? await world.storedText(of: 6, modelSet: Self.modelSet)) != nil
        }
        try await settled(service)

        #expect(Self.texts(world) == ["text 5", "text 6"])
        #expect(ledger.stoppedAnswers == 0 && ledger.prompts.count == 2)
        #expect(!world.log.contains("draw 6") && session.events.status(of: 6) == .translating)

        // The reader turns the page: page 6 is drawn from its text, and the model is not asked.
        await service.show(session, onScreen: [6], ahead: [7], behind: [5])
        try await eventually("page 6 to be translated") { session.events.isTranslated(6) }
        try await settled(service)
        #expect(ledger.prompts.count == 2)
    }

    // MARK: Stopping

    /// A page that is no longer wanted stops the model within its answer; what the model had
    /// written is thrown away, and the page is cancelled, not failed.
    @Test func aPageThatLeavesTheWindowStopsTheModelAndWritesNothing() async throws {
        let (world, ledger) = try await Self.world()
        let service = world.service()
        let session = await service.open()
        ledger.hold(call: 1)

        await service.show(session, onScreen: [1])
        try await eventually("page 1 to be with the model") { ledger.generating == 1 }
        await service.show(session, onScreen: [])
        try await eventually("the model to stop") { ledger.stoppedAnswers == 1 && ledger.generating == 0 }
        try await settled(service)

        #expect(try await world.storedText(of: 1, modelSet: Self.modelSet) == nil)
        #expect(!world.hasPatchFile(of: 1))
        #expect(!Self.hasFailed(session.events, 1))
        #expect(session.events.status(of: 1) == .translating)
        // The model stays for the next page, which it translates as usual.
        #expect(ledger.alive == 1)
        await service.show(session, onScreen: [2])
        try await eventually("page 2 to be translated") { session.events.isTranslated(2) }
        #expect(ledger.loaded == 1)
    }

    /// An answer ended by `stop()` on the model, in no task the service cancelled: the page
    /// is still wanted, so it is not failed and not kept in part. It is asked for again.
    @Test func aPageWhoseAnswerWasStoppedFromOutsideIsAskedForAgain() async throws {
        let (world, ledger) = try await Self.world()
        let service = world.service()
        let session = await service.open()
        ledger.hold(call: 1)

        await service.show(session, onScreen: [1])
        try await eventually("page 1 to be with the model") { ledger.generating == 1 }
        ledger.stop()
        try await eventually("page 1 to be translated") { session.events.isTranslated(1) }

        #expect(ledger.stoppedAnswers == 1 && ledger.prompts.count == 2)
        #expect(!Self.hasFailed(session.events, 1))
        #expect(try await world.storedText(of: 1, modelSet: Self.modelSet)?.regions.first?.translation == "你好")
    }

    /// Closing the last reader cancels its pages, stops the model and lets it go: nothing
    /// holds the model's memory after the answer in work has ended.
    @Test func closingTheLastReaderStopsTheModelAndLetsItGo() async throws {
        let (world, ledger) = try await Self.world()
        let service = world.service()
        let session = await service.open()
        ledger.hold(call: 1)

        await service.show(session, onScreen: [1], ahead: [2])
        try await eventually("page 1 to be with the model") { ledger.generating == 1 }
        await service.perform(.close(session.id))

        try await eventually("the model to be let go") { ledger.alive == 0 }
        #expect(ledger.stops >= 1, "the model itself was not told to stop")
        #expect(ledger.stoppedAnswers == 1 && ledger.prompts.count == 1)
        #expect(try await world.storedText(of: 1, modelSet: Self.modelSet) == nil)
        try await eventually("the session's events to end") { session.events.hasEnded }
        #expect(!Self.hasFailed(session.events, 1))
    }

    /// The model keeps running while another reader is open, and only its own page stops.
    @Test func closingOneOfTwoReadersKeepsTheModel() async throws {
        let (world, ledger) = try await Self.world()
        let service = world.service()
        let first = await service.open(), second = await service.open(gid: "77")
        ledger.hold(call: 1)

        await service.show(first, onScreen: [1])
        try await eventually("page 1 to be with the model") { ledger.generating == 1 }
        await service.show(second, onScreen: [3])
        await service.perform(.close(first.id))
        try await eventually("the second reader's page to be translated") { second.events.isTranslated(3) }

        #expect(ledger.alive == 1 && ledger.loaded == 1)
        #expect(ledger.stoppedAnswers == 1 && ledger.stops == 0)
    }

    /// Before the model's file is deleted the answer in work has ended and the model is gone.
    @Test func aModelAboutToBeDeletedIsStoppedAndLetGoFirst() async throws {
        let (world, ledger) = try await Self.world()
        let service = world.service()
        let session = await service.open()
        ledger.hold(call: 1)

        await service.show(session, onScreen: [1])
        try await eventually("page 1 to be with the model") { ledger.generating == 1 }
        await service.perform(.unload([TranslatorChoice.hyMT2.artifact]))

        // The call under way returned before `unload` did.
        #expect(ledger.generating == 0 && ledger.stoppedAnswers == 1)
        try await eventually("the model to be let go") { ledger.alive == 0 }
        #expect(try await world.storedText(of: 1, modelSet: Self.modelSet) == nil)
    }

    /// Another choice of translator lets the model go and starts the pages again with the
    /// new one; nothing the model was writing is kept under either.
    @Test func choosingAnotherTranslatorLetsTheModelGo() async throws {
        let (world, ledger) = try await Self.world()
        let service = world.service()
        let session = await service.open()
        ledger.hold(call: 1)

        await service.show(session, onScreen: [1])
        try await eventually("page 1 to be with the model") { ledger.generating == 1 }
        world.set { $0.setup = TranslationWorld.setup() }
        await service.show(session, onScreen: [1])
        try await eventually("page 1 to be translated by the other translator") { session.events.isTranslated(1) }

        try await eventually("the model to be let go") { ledger.alive == 0 }
        #expect(ledger.prompts.count == 1 && ledger.stoppedAnswers == 1)
        #expect(try await world.storedText(of: 1, modelSet: Self.modelSet) == nil)
        #expect(try await world.storedText(of: 1)?.regions.first?.translation == "你好")
    }
}
