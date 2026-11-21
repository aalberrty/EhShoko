import CoreGraphics
import EhModels
import EhPageTranslation
import Foundation
import Testing
@testable import EhCore

/// The service under heat, Low Power Mode, a memory warning, a changed choice and failures.
@Suite struct PageTranslationServiceRulesTests {
    static let gid = TranslationWorld.gid

    static func texts(_ world: TranslationWorld) -> [String] { world.log.filter { $0.hasPrefix("text") } }

    // MARK: Heat and power

    @Test func atSeriousHeatOnlyThePagesOnScreenAreTranslated() async throws {
        let world = try await TranslationWorld()
        world.set { $0.heat = .serious }
        let service = world.service()
        let session = await service.open()

        await service.show(session, onScreen: [5], ahead: [6, 7], behind: [4])
        try await eventually("page 5 to be translated") { session.events.isTranslated(5) }
        try await settled(service)
        #expect(Self.texts(world) == ["text 5"])

        // Cooler again: the next time the reader moves, the pages ahead are worked on.
        world.set { $0.heat = .fair }
        await service.show(session, onScreen: [6], ahead: [7, 8], behind: [5])
        try await eventually("the window to be translated") { [5, 6, 7, 8].allSatisfy(session.events.isTranslated) }
        #expect(Self.texts(world) == ["text 5", "text 6", "text 7", "text 8"])
    }

    @Test func heatThatRisesWhileReadingStopsTheWorkAhead() async throws {
        let world = try await TranslationWorld()
        let service = world.service()
        let session = await service.open()
        world.textGates.hold(5)

        await service.show(session, onScreen: [5], ahead: [6, 7])
        try await eventually("page 5 to be in work") { world.log.contains("text 5") }
        world.set { $0.heat = .critical }
        world.textGates.release(5)
        try await eventually("page 5 to be translated") { session.events.isTranslated(5) }
        try await settled(service)

        #expect(Self.texts(world) == ["text 5"])
    }

    @Test func inLowPowerModeOnePageAheadAtMostAndNotThePageBefore() async throws {
        let world = try await TranslationWorld()
        world.set { $0.isLowPower = true }
        let service = world.service()
        let session = await service.open()

        await service.show(session, onScreen: [5], ahead: [6, 7], behind: [4])
        try await eventually("pages 5 and 6 to be translated") { session.events.isTranslated(5) && session.events.isTranslated(6) }
        try await settled(service)

        #expect(Self.texts(world) == ["text 5", "text 6"])
    }

    @Test func aStoredPageAheadIsShownWhateverTheHeat() async throws {
        let world = try await TranslationWorld()
        world.set { $0.heat = .critical }
        await world.writer.add(TranslationWorld.storedPage(7))
        let patch = Patch(rect: PixelRect(x: 1, y: 1, width: 2, height: 2), pixels: Data(repeating: 255, count: 16))
        _ = try await PatchFile.write(
            [patch], imageWidth: 47, imageHeight: 64, colorSpace: CGColorSpaceCreateDeviceRGB(), to: world.patchFile(of: 7)
        )
        let service = world.service()
        let session = await service.open()

        await service.show(session, onScreen: [5], ahead: [6, 7])
        try await eventually("the stored page to be shown") { session.events.isTranslated(7) }

        // Showing what is stored is no work: one read and one look for a file.
        #expect(session.events.statuses(of: 7).count == 1)
    }

    // MARK: Memory

    @Test func aMemoryWarningLetsTheRepaintModelGoAndKeepsOnlyThePagesOnScreen() async throws {
        let world = try await TranslationWorld(setup: TranslationWorld.setup(repaint: .lamaManga))
        world.set { $0.drawingAsksForTheRepaintModel = true }
        let service = world.service()
        let session = await service.open()
        world.textGates.hold(6)

        await service.show(session, onScreen: [5], ahead: [6, 7])
        try await eventually("page 5 to be translated and page 6 to be in work") {
            session.events.isTranslated(5) && world.log.contains("text 6")
        }
        // The repaint model was loaded by the first block that asked for it, once.
        #expect(world.value(\.inpainterLoads) == 1)
        if case .ready = await service.inpainterState {} else { Issue.record("the repaint model is not loaded") }

        await service.perform(.memoryWarning)

        if case .unloaded = await service.inpainterState {} else { Issue.record("the repaint model was kept") }
        world.textGates.release(6)
        try await settled(service)
        // Page 6 was ahead: its work was stopped and wrote nothing; page 7 was never started.
        #expect(try await world.storedText(of: 6) == nil && !world.hasPatchFile(of: 6))
        #expect(!world.log.contains("text 7"))
        // The three models stay: they are what the page on screen needs.
        if case .ready = await service.pipelineState {} else { Issue.record("the models were let go") }

        // The reader moves on: the queue is whole again, and the repaint model comes back
        // with the first block that needs it.
        await service.show(session, onScreen: [6], ahead: [7])
        try await eventually("pages 6 and 7 to be translated") { session.events.isTranslated(6) && session.events.isTranslated(7) }
        #expect(world.value(\.inpainterLoads) == 2)
        #expect(world.pipelineLoads.count == 1)
    }

    @Test func aPageWithoutTextOnArtworkNeverLoadsTheRepaintModel() async throws {
        let world = try await TranslationWorld(setup: TranslationWorld.setup(repaint: .lamaManga))
        let service = world.service()
        let session = await service.open()

        await service.show(session, onScreen: [1], ahead: [2])
        try await eventually("both pages to be translated") { session.events.isTranslated(1) && session.events.isTranslated(2) }

        #expect(world.value(\.inpainterLoads) == 0)
        #expect(world.patchFile(of: 1).path.contains("lamamanga"))
    }

    @Test func aPageWhoseRepaintFailedIsNotKeptAsTheRepaintModelsDrawing() async throws {
        let world = try await TranslationWorld(setup: TranslationWorld.setup(repaint: .lamaManga))
        world.set { $0.failedRepaints = 1 }
        let service = world.service()
        let session = await service.open()

        await service.show(session, onScreen: [1])
        try await eventually("page 1 to be shown") { session.events.isTranslated(1) }

        // Shown now, from a file that says it was filled; the next time it is drawn again.
        guard case let .translated(overlay) = session.events.status(of: 1) else { return }
        #expect(overlay.variant == "k2xl768.cpt2.jmt1.t1.fill.r1")
        #expect(FileManager.default.fileExists(atPath: overlay.patchFile.path))
        #expect(!world.hasPatchFile(of: 1))
        #expect(session.events.report(of: 1)?.failedRepaints == 1)
    }

    // MARK: A changed choice

    @Test func aChangedModelSetStartsAgainAndNeverMixesResults() async throws {
        let world = try await TranslationWorld()
        let service = world.service()
        let session = await service.open()
        await service.show(session, onScreen: [1])
        try await eventually("page 1 to be translated") { session.events.isTranslated(1) }

        let other = PageTranslationModelSet(detector: .v4s)
        world.set { $0.setup = TranslationWorld.setup(other) }
        await service.show(session, onScreen: [1])
        let overlay = PageTranslationOverlay(patchFile: world.patchFile(of: 1), variant: "v4s.cpt2.jmt1.t1.fill.r1")
        try await eventually("page 1 to be translated with the other models") {
            session.events.status(of: 1) == .translated(overlay)
        }

        // The page stored under the first set is not shown for the second: it is made anew,
        // with the second set's models, and each result stays under its own key.
        #expect(world.pipelineLoads.map(\.modelSet) == [.default, other])
        #expect(world.log == ["text 1", "draw 1", "text 1", "draw 1"])
        #expect(try await world.storedText(of: 1, modelSet: other)?.modelSetKey == other.key)
        #expect(try await world.storedText(of: 1)?.modelSetKey == PageTranslationModelSet.default.key)
    }

    @Test func modelsAboutToBeDeletedAreLetGoFirst() async throws {
        let world = try await TranslationWorld()
        let service = world.service()
        let session = await service.open()
        await service.show(session, onScreen: [1])
        try await eventually("page 1 to be translated") { session.events.isTranslated(1) }

        // Another model's deletion is none of the service's business.
        await service.perform(.unload([.bigLama]))
        if case .ready = await service.pipelineState {} else { Issue.record("the models were let go for nothing") }

        await service.perform(.unload([.k2xl]))
        if case .unloaded = await service.pipelineState {} else { Issue.record("a model about to be deleted is still loaded") }

        // Still installed after all: the next page loads them again.
        await service.show(session, onScreen: [2])
        try await eventually("page 2 to be translated") { session.events.isTranslated(2) }
        #expect(world.pipelineLoads.count == 2)
    }

    // MARK: Failures

    @Test func aPageWhoseImageCannotBeFetchedFailsAndRetryTriesAgain() async throws {
        let world = try await TranslationWorld()
        world.set { $0.unavailablePages = [1] }
        let service = world.service()
        let session = await service.open()

        await service.show(session, onScreen: [1], ahead: [2])
        try await eventually("page 1 to fail") { session.events.status(of: 1) == .failed(.imageUnavailable) }
        // A failed page does not hold the queue up.
        try await eventually("page 2 to be translated") { session.events.isTranslated(2) }

        world.set { $0.unavailablePages = [] }
        await service.perform(.retry(session.id, pageIndex: 1))
        try await eventually("page 1 to be translated") { session.events.isTranslated(1) }
        #expect(session.events.statuses(of: 1).dropLast() == [.loadingModels, .translating, .failed(.imageUnavailable), .translating])
        #expect(world.fetches(of: 1) == 2)
    }

    @Test func modelsThatDoNotLoadFailTheirPagesAndRetryLoadsThemAgain() async throws {
        let world = try await TranslationWorld()
        world.set { $0.failsToLoadModels = true }
        let service = world.service()
        let session = await service.open()

        await service.show(session, onScreen: [1], ahead: [2])
        try await eventually("both pages to fail") {
            session.events.status(of: 1) == .failed(.modelsFailedToLoad) && session.events.status(of: 2) == .failed(.modelsFailedToLoad)
        }
        #expect(world.pipelineLoads.count == 1 && world.log.isEmpty)

        world.set { $0.failsToLoadModels = false }
        await service.perform(.retry(session.id, pageIndex: 1))
        try await eventually("both pages to be translated") { session.events.isTranslated(1) && session.events.isTranslated(2) }
        #expect(world.pipelineLoads.count == 2)
    }

    @Test func anAnimatedPageIsSkippedAndNotFetchedAgain() async throws {
        let world = try await TranslationWorld()
        world.set { $0.animatedPages = [3] }
        let service = world.service()
        let session = await service.open()

        await service.show(session, onScreen: [3])
        try await eventually("page 3 to be skipped") { session.events.status(of: 3) == .skipped }
        await service.show(session, onScreen: [4])
        await service.show(session, onScreen: [3])
        try await settled(service)

        #expect(session.events.statuses(of: 3).filter { $0 == .skipped }.count == 2)
        #expect(world.fetches(of: 3) == 1)
        #expect(try await world.storedText(of: 3) == nil && !world.log.contains("text 3"))
    }

    @Test func bytesThatAreNoImageFailThePage() async throws {
        let world = try await TranslationWorld()
        world.set { $0.unreadablePages = [1] }
        let service = world.service()
        let session = await service.open()

        await service.show(session, onScreen: [1])
        try await eventually("page 1 to fail") { session.events.status(of: 1) == .failed(.imageUnreadable) }

        #expect(world.log.isEmpty)
    }

    @Test func retryOnATranslatedPageDrawsItAgainFromItsText() async throws {
        let world = try await TranslationWorld()
        let service = world.service()
        let session = await service.open()
        await service.show(session, onScreen: [1])
        try await eventually("page 1 to be translated") { session.events.isTranslated(1) }
        // The reader could not show the file.
        try Data("damaged".utf8).write(to: world.patchFile(of: 1))

        await service.perform(.retry(session.id, pageIndex: 1))
        try await eventually("page 1 to be drawn again") {
            session.events.statuses(of: 1).filter { if case .translated = $0 { true } else { false } }.count == 2
        }

        #expect(world.log == ["text 1", "draw 1", "draw 1"])
        let file = try await PatchFile.read(from: world.patchFile(of: 1))
        #expect(file.placements.count == 1)
    }

    @Test func retryOnAPageThatIsNotWantedOrNotDoneDoesNothing() async throws {
        let world = try await TranslationWorld()
        let service = world.service()
        let session = await service.open()
        world.textGates.hold(1)
        await service.show(session, onScreen: [1])
        try await eventually("page 1 to be in work") { world.log.contains("text 1") }

        await service.perform(.retry(session.id, pageIndex: 1))
        await service.perform(.retry(session.id, pageIndex: 99))
        world.textGates.release(1)
        try await eventually("page 1 to be translated") { session.events.isTranslated(1) }

        #expect(world.log == ["text 1", "draw 1"])
    }
}
