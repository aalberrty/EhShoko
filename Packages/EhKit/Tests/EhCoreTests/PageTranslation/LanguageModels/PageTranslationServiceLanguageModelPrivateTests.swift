import EhModels
import EhPageTranslation
import Foundation
import Testing
@testable import EhCore

/// The opt-in tier for the service with a language model: the real service, the app's own
/// loader and the smallest real model file, under a stub detector and reader
/// (`PrivateTranslationFolder`). It shows what the stub model cannot: that a reader's page
/// reaches llama.cpp and comes back, and that closing the reader ends a real answer at once.
@Suite(.privateTranslationFolder, .serialized) struct PageTranslationServiceLanguageModelPrivateTests {
    /// Long enough that its answer takes seconds on a Mac's CPU.
    static let line = "今日は朝から雨が降っていて、駅まで歩くあいだに靴がすっかり濡れてしまいました。帰りに新しい傘を買おうと思います。"

    @Test(.timeLimit(.minutes(30)))
    func aPageIsTranslatedByTheRealModelAndClosingTheReaderEndsItsAnswerAtOnce() async throws {
        let candidate = LanguageModelCandidate.smallest
        let modelSet = PageTranslationModelSet(translator: candidate.choice)
        let world = try await TranslationWorld(setup: TranslationWorld.setup(modelSet))
        let file = try candidate.url()
        world.set {
            $0.languageModelFile = file
            $0.readerText = Self.line
        }
        let service = world.service()
        let session = await service.open()
        let clock = ContinuousClock()

        await service.show(session, onScreen: [1])
        try await eventually("page 1 to be translated by the model") { session.events.isTranslated(1) }
        let translation = try #require(try await world.storedText(of: 1, modelSet: modelSet)?.regions.first?.translation)
        // Chinese: a model that computes wrongly, or was not asked properly, answers otherwise.
        let chinese = translation.unicodeScalars.count { (0x4E00...0x9FFF).contains($0.value) }
        #expect(chinese >= 8, "\(translation)")
        let report = try #require(session.events.report(of: 1))

        // A second page, and the reader is closed while the model writes its answer.
        await service.show(session, onScreen: [2], behind: [1])
        try await eventually("page 2 to be with the model") { world.log.contains("text 2") }
        try await Task.sleep(for: .seconds(2))
        let closeStart = clock.now
        await service.perform(.close(session.id))
        try await eventually("the model's call to return") { await service.textSlot == nil }
        let closing = clock.now - closeStart

        #expect(closing < .seconds(5), "closing took \(closing)")
        #expect(try await world.storedText(of: 2, modelSet: modelSet) == nil)
        if case .unloaded = await service.pipelineState {} else { Issue.record("the model was kept after the last reader") }
        print("""
        PageTranslationService opt-in, \(candidate.name): models loaded and page 1 translated in \(report.total) \
        (waiting for the models \(report.waitingForModels)); closing the reader two seconds into page 2 \
        ended the model's answer after \(closing)
          \(Self.line)
          \(translation)
        """)
    }
}
