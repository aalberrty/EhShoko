import CoreGraphics
import EhModels
import EhPageTranslation
import Foundation
import Testing
@testable import EhCore

/// The switch for drawn sound effects in the service: a page stored under one rule is never
/// shown under the other, and a change while a reader is open is taken as a changed model
/// choice is, on the reader's next window.
@Suite struct PageTranslationServiceSoundEffectsTests {
    static let on = PageTranslationModelSet(translatesSoundEffects: true)

    /// Page 1 stored with the switch off, its text and its patch file.
    static func storeWithTheSwitchOff(_ world: TranslationWorld) async throws {
        await world.writer.add(TranslationWorld.storedPage(1))
        let patch = Patch(rect: PixelRect(x: 1, y: 1, width: 2, height: 2), pixels: Data(repeating: 255, count: 16))
        _ = try await PatchFile.write(
            [patch], imageWidth: TranslationWorld.width(of: 1), imageHeight: TranslationWorld.height,
            colorSpace: CGColorSpaceCreateDeviceRGB(),
            to: world.patchFile(of: 1, variant: TranslationWorld.setup().variant)
        )
    }

    @Test func aPageStoredWithTheSwitchOffIsTranslatedAgainWithItOn() async throws {
        let world = try await TranslationWorld(setup: TranslationWorld.setup(Self.on))
        try await Self.storeWithTheSwitchOff(world)
        let service = world.service()
        let session = await service.open()

        await service.show(session, onScreen: [1])
        let overlay = PageTranslationOverlay(patchFile: world.patchFile(of: 1), variant: "k2xl768.cpt2.jmt1.t1.sfx.fill.r1")
        try await eventually("page 1 to be translated with the switch on") { session.events.status(of: 1) == .translated(overlay) }

        // Not the stored page: the models were loaded and the page made anew, under its own key.
        #expect(world.pipelineLoads.map(\.modelSet) == [Self.on])
        #expect(world.log == ["text 1", "draw 1"])
        #expect(try await world.storedText(of: 1, modelSet: Self.on)?.modelSetKey == Self.on.key)
        // The first use in a process keeps only the current key's pages, as for a changed
        // model: the page stored with the switch off is gone, its patch file too.
        #expect(try await world.storedText(of: 1) == nil)
        #expect(!FileManager.default.fileExists(atPath: world.patchFile(of: 1, variant: TranslationWorld.setup().variant).path))
    }

    @Test func withTheSwitchBackOffThePageStoredThenIsShownWithNoModelLoaded() async throws {
        let world = try await TranslationWorld()
        try await Self.storeWithTheSwitchOff(world)
        await world.writer.add(TranslationWorld.storedPage(1, modelSet: Self.on))
        let service = world.service()
        let session = await service.open()

        await service.show(session, onScreen: [1])
        try await eventually("the stored page to be shown") { session.events.isTranslated(1) }
        #expect(world.pipelineLoads.isEmpty)
        #expect(world.log.isEmpty)
        #expect(session.events.status(of: 1) == .translated(PageTranslationOverlay(
            patchFile: world.patchFile(of: 1), variant: "k2xl768.cpt2.jmt1.t1.fill.r1"
        )))
    }

    /// Turned on in Settings while a reader is open: nothing changes until the reader next
    /// sends its window (a page turn), then all work is dropped and the pages in the window
    /// are translated again under the new rule. The page on screen keeps its old drawing
    /// until the new one is ready.
    @Test func aChangeWhileAReaderIsOpenIsTakenOnItsNextWindow() async throws {
        let world = try await TranslationWorld()
        let service = world.service()
        let session = await service.open()
        await service.show(session, onScreen: [1])
        try await eventually("page 1 to be translated") { session.events.isTranslated(1) }

        world.set { $0.setup = TranslationWorld.setup(Self.on) }
        await service.show(session, onScreen: [1], ahead: [2])
        let overlay = PageTranslationOverlay(patchFile: world.patchFile(of: 1), variant: "k2xl768.cpt2.jmt1.t1.sfx.fill.r1")
        try await eventually("page 1 to be translated again with the switch on") {
            session.events.status(of: 1) == .translated(overlay) && session.events.isTranslated(2)
        }
        #expect(world.pipelineLoads.map(\.modelSet) == [.default, Self.on])
        #expect(world.log.filter { $0 == "text 1" }.count == 2)
    }
}
