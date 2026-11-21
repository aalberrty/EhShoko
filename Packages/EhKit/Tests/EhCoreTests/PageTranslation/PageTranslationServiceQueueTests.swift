import EhModels
import EhPageTranslation
import Foundation
import Testing
@testable import EhCore

/// The queue: its order, one page in each half, and what a cancelled page leaves behind.
@Suite struct PageTranslationServiceQueueTests {
    static let gid = TranslationWorld.gid
    static let key = PageTranslationModelSet.default.key

    static func texts(_ world: TranslationWorld) -> [String] { world.log.filter { $0.hasPrefix("text") } }
    static func draws(_ world: TranslationWorld) -> [String] { world.log.filter { $0.hasPrefix("draw") } }

    @Test func pagesAreServedOnScreenFirstThenAheadThenTheOneBefore() async throws {
        let world = try await TranslationWorld()
        let service = world.service()
        let session = await service.open()

        await service.show(session, onScreen: [5], ahead: [6, 7, 8], behind: [4])
        try await eventually("the window to be translated") { [4, 5, 6, 7, 8].allSatisfy(session.events.isTranslated) }

        #expect(Self.texts(world) == ["text 5", "text 6", "text 7", "text 8", "text 4"])
        #expect(Self.draws(world) == ["draw 5", "draw 6", "draw 7", "draw 8", "draw 4"])
        #expect(world.pipelineLoads.count == 1)
    }

    @Test func theCoreMLTranslatorWorksThreePagesAhead() async throws {
        let world = try await TranslationWorld()
        let service = world.service()
        let session = await service.open()

        await service.show(session, onScreen: [5], ahead: [6, 7, 8, 9], behind: [4])
        try await eventually("the window to be translated") { [4, 5, 6, 7, 8].allSatisfy(session.events.isTranslated) }
        try await settled(service)

        #expect(Self.texts(world) == ["text 5", "text 6", "text 7", "text 8", "text 4"])
        // The fourth page ahead waits: it is wanted, and not worked on.
        #expect(session.events.status(of: 9) == .translating)
    }

    @Test func aLanguageModelWorksOnePageAhead() async throws {
        let world = try await TranslationWorld(setup: TranslationWorld.setup(PageTranslationModelSet(translator: .hyMT2)))
        let service = world.service()
        let session = await service.open()

        await service.show(session, onScreen: [5], ahead: [6, 7, 8], behind: [4])
        try await eventually("the pages to be translated") { [4, 5, 6].allSatisfy(session.events.isTranslated) }
        try await settled(service)

        #expect(Self.texts(world) == ["text 5", "text 6", "text 4"])
        #expect(session.events.status(of: 7) == .translating && session.events.status(of: 8) == .translating)
    }

    /// The queue's rule: at most one page is ever in each half, the two halves
    /// work side by side, and the first half takes no further page while one waits for the
    /// second with its bitmap.
    @Test func atMostOnePageIsEverInEachHalf() async throws {
        let world = try await TranslationWorld()
        let service = world.service()
        let session = await service.open()
        world.drawGates.hold(1)

        await service.show(session, onScreen: [1], ahead: [2, 3])
        // Page 1 is being drawn while page 2 is found, read and translated.
        try await eventually("page 2's first half to end") {
            guard world.log.contains("draw 1"), world.log.contains("text 2") else { return false }
            return await service.textSlot == nil
        }
        #expect(await service.drawSlot?.key.index == 1)
        #expect(world.value(\.bothHalvesWereBusy))
        // Page 2 waits for the second half; page 3 is not started behind it.
        try await Task.sleep(for: .milliseconds(50))
        #expect(!world.log.contains("text 3") && !world.log.contains("draw 2"))
        #expect(await service.textSlot == nil)

        world.drawGates.release(1)
        try await eventually("all three pages to be translated") { [1, 2, 3].allSatisfy(session.events.isTranslated) }

        #expect(world.value(\.mostInText) == 1 && world.value(\.mostInDrawing) == 1)
        #expect(Self.texts(world) == ["text 1", "text 2", "text 3"])
        #expect(Self.draws(world) == ["draw 1", "draw 2", "draw 3"])
    }

    @Test func twoReadersShareTheTwoHalves() async throws {
        let world = try await TranslationWorld()
        let service = world.service()
        let first = await service.open(), second = await service.open(gid: "77")

        await service.show(first, onScreen: [1], ahead: [2])
        await service.show(second, onScreen: [3], ahead: [4])
        try await eventually("both readers' pages to be translated") {
            [1, 2].allSatisfy(first.events.isTranslated) && [3, 4].allSatisfy(second.events.isTranslated)
        }

        #expect(world.value(\.mostInText) == 1 && world.value(\.mostInDrawing) == 1)
        #expect(world.pipelineLoads.count == 1)
        // The models stay while one reader is still open.
        await service.perform(.close(first.id))
        if case .ready = await service.pipelineState {} else { Issue.record("the models were let go too early") }
        await service.perform(.close(second.id))
        if case .unloaded = await service.pipelineState {} else { Issue.record("the models were kept after the last reader") }
    }

    // MARK: Cancelling

    /// The rule for cancelling: a page cancelled while it is found, read and translated
    /// writes nothing, neither its text nor a patch file.
    @Test func aPageCancelledInItsFirstHalfWritesNothing() async throws {
        let world = try await TranslationWorld()
        let service = world.service()
        let session = await service.open()
        world.textGates.hold(1)

        await service.show(session, onScreen: [1])
        try await eventually("page 1 to be in the detector") { world.log.contains("text 1") }
        // Translate is switched off while the detector's call is under way.
        await service.show(session, onScreen: [])
        world.textGates.release(1)
        try await settled(service)

        #expect(try await world.storedText(of: 1) == nil)
        await world.writer.flush()
        await world.writer.waitUntilWritten()
        #expect(try await world.database.pageTranslationCount(gid: Self.gid, modelSetKey: Self.key) == 0)
        #expect(!world.hasPatchFile(of: 1) && Self.draws(world).isEmpty)
        #expect(session.events.status(of: 1) == .translating)
    }

    @Test func aPageTheReaderLeftBehindWritesNothingAndTheNextOneIsTranslated() async throws {
        let world = try await TranslationWorld()
        let service = world.service()
        let session = await service.open()
        world.textGates.hold(1)

        await service.show(session, onScreen: [1])
        try await eventually("page 1 to be in the detector") { world.log.contains("text 1") }
        // A jump with the slider: page 1 is no longer wanted.
        await service.show(session, onScreen: [30])
        // The detector's call cannot be interrupted: its half stays taken until it returns.
        try await Task.sleep(for: .milliseconds(50))
        #expect(await service.textSlot?.key.index == 1)
        #expect(!world.log.contains("text 30"))

        world.textGates.release(1)
        try await eventually("page 30 to be translated") { session.events.isTranslated(30) }

        #expect(Self.texts(world) == ["text 1", "text 30"] && world.value(\.mostInText) == 1)
        #expect(try await world.storedText(of: 1) == nil)
        #expect(!world.hasPatchFile(of: 1) && world.hasPatchFile(of: 30))
    }

    @Test func aPageCancelledWhileItIsDrawnKeepsItsTextAndWritesNoPatchFile() async throws {
        let world = try await TranslationWorld()
        let service = world.service()
        let session = await service.open()
        world.drawGates.hold(1)

        await service.show(session, onScreen: [1])
        try await eventually("page 1 to be in drawing") { world.log.contains("draw 1") }
        await service.show(session, onScreen: [])
        world.drawGates.release(1)
        try await settled(service)

        // Its first half ended before the cancel: that text is the expensive part and is kept.
        #expect(try await world.storedText(of: 1)?.hasTranslatedText == true)
        #expect(!world.hasPatchFile(of: 1))
        // Asked for again, it is drawn from that text: no model work a second time.
        await service.show(session, onScreen: [1])
        try await eventually("page 1 to be drawn") { session.events.isTranslated(1) }
        #expect(world.log == ["text 1", "draw 1", "draw 1"])
    }

    @Test func aDrawingThatDoesNotNoticeItsCancelStillWritesNothing() async throws {
        let world = try await TranslationWorld()
        world.set { $0.drawingIgnoresCancellation = true }
        let service = world.service()
        let session = await service.open()
        world.drawGates.hold(1)

        await service.show(session, onScreen: [1])
        try await eventually("page 1 to be in drawing") { world.log.contains("draw 1") }
        await service.show(session, onScreen: [])
        world.drawGates.release(1)
        try await settled(service)

        #expect(!world.hasPatchFile(of: 1))
        #expect(!session.events.isTranslated(1))
    }

    @Test func switchingTranslateOffWritesWhatIsWaitingAndKeepsTheModels() async throws {
        let world = try await TranslationWorld()
        let service = world.service()
        let session = await service.open()

        await service.show(session, onScreen: [1])
        try await eventually("page 1 to be translated") { session.events.isTranslated(1) }
        await service.show(session, onScreen: [])
        await world.writer.waitUntilWritten()

        #expect(try await world.database.translatedPageIndices(gid: Self.gid, modelSetKey: Self.key) == [1])
        // Switched on again in the same reader, the load is not paid twice.
        if case .ready = await service.pipelineState {} else { Issue.record("the models were let go") }
        await service.show(session, onScreen: [2])
        try await eventually("page 2 to be translated") { session.events.isTranslated(2) }
        #expect(world.pipelineLoads.count == 1)
        #expect(session.events.statuses(of: 2).first == .translating)
    }

    // MARK: Closing

    @Test func closingCancelsEverythingWritesWhatIsWaitingAndLetsTheModelsGo() async throws {
        let world = try await TranslationWorld()
        let service = world.service()
        // As the reader's model uses it: through the client.
        let session = service.client.openSession(Self.gid)
        let events = SessionEvents()
        events.collect(session.events)
        world.textGates.hold(2)

        session.setWindow(TranslationWorld.window(onScreen: [1], ahead: [2]))
        try await eventually("page 1 to be translated and page 2 to be in work") {
            events.isTranslated(1) && world.log.contains("text 2")
        }
        session.close()
        try await eventually("the session's events to end") { events.hasEnded }
        world.textGates.release(2)
        try await eventually("the service to be empty") {
            guard await service.isIdle else { return false }
            return await service.sessions.isEmpty
        }
        await world.writer.waitUntilWritten()

        // Page 1 is written without waiting for the writer's delay; page 2 left nothing.
        #expect(try await world.database.translatedPageIndices(gid: Self.gid, modelSetKey: Self.key) == [1])
        #expect(try await world.storedText(of: 2) == nil && !world.hasPatchFile(of: 2))
        if case .unloaded = await service.pipelineState {} else { Issue.record("the models were kept") }

        // The next reader pays the load again, as it must.
        let next = await service.open()
        await service.show(next, onScreen: [3])
        try await eventually("page 3 to be translated") { next.events.isTranslated(3) }
        #expect(world.pipelineLoads.count == 2)
    }

    @Test func aSessionsCallsTakeEffectInTheOrderTheyWereMade() async throws {
        let world = try await TranslationWorld()
        let service = world.service()
        let session = service.client.openSession(Self.gid)
        let events = SessionEvents()
        events.collect(session.events)

        // Three page turns in one go: only the last window counts.
        for page in [1, 2, 3] { session.setWindow(TranslationWorld.window(onScreen: [page])) }
        try await eventually("page 3 to be translated") { events.isTranslated(3) }
        try await settled(service)

        #expect(await service.sessions.values.first?.window == TranslationWorld.window(onScreen: [3]))
        #expect(await service.sessions.values.first?.pages.keys.sorted() == [3])
        session.close()
        try await eventually("the session to close") { await service.sessions.isEmpty }
    }

    @Test func aSessionThatIsLetGoWithoutBeingClosedIsClosed() async throws {
        let world = try await TranslationWorld()
        let service = world.service()
        let events = SessionEvents()
        do {
            let session = service.client.openSession(Self.gid)
            events.collect(session.events)
            session.setWindow(TranslationWorld.window(onScreen: [1]))
            try await eventually("page 1 to be translated") { events.isTranslated(1) }
        }

        try await eventually("the session to close") { await service.sessions.isEmpty }
        try await eventually("its events to end") { events.hasEnded }
        try await eventually("the models to be let go") {
            if case .unloaded = await service.pipelineState { return true }
            return false
        }
    }
}
