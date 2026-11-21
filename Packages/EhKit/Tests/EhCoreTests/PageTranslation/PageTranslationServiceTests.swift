import CoreGraphics
import EhModels
import EhPageTranslation
import Foundation
import Testing
@testable import EhCore

/// The service from a page that is new to one that is stored.
@Suite struct PageTranslationServiceTests {
    static let gid = TranslationWorld.gid
    static let key = PageTranslationModelSet.default.key

    @Test func openingASessionLoadsAndFetchesNothing() async throws {
        let world = try await TranslationWorld()
        let service = world.service()

        _ = await service.open()

        #expect(world.value(\.prepares) == 1)
        #expect(world.pipelineLoads.isEmpty && world.log.isEmpty && world.value(\.fetches).isEmpty)
        #expect(await service.isIdle)
    }

    @Test func aNewPageIsFoundReadTranslatedDrawnAndKept() async throws {
        let world = try await TranslationWorld()
        let service = world.service()
        let session = await service.open()

        await service.show(session, onScreen: [1])
        try await eventually("page 1 to be translated") { session.events.isTranslated(1) }

        let overlay = PageTranslationOverlay(patchFile: world.patchFile(of: 1), variant: "k2xl768.cpt2.jmt1.t1.fill.r1")
        #expect(session.events.statuses(of: 1) == [.loadingModels, .translating, .translated(overlay)])
        #expect(world.log == ["text 1", "draw 1"])
        #expect(world.pipelineLoads.count == 1 && world.fetches(of: 1) == 1)

        // Its text: the line that was read and translated, and the sound effect's box.
        let stored = try #require(try await world.storedText(of: 1))
        #expect(stored.regions.map(\.kind) == [.dialogue, .soundEffect])
        #expect(stored.regions.map(\.translation) == ["你好", ""])
        #expect(stored.imageWidth == 41 && stored.imageHeight == 64 && stored.createdAt == TranslationWorld.now)

        // Its patch file, as the reader's page view reads it.
        let file = try await PatchFile.read(from: overlay.patchFile)
        #expect(file.imageWidth == 41 && file.placements.map(\.pageRect) == [PixelRect(x: 2, y: 3, width: 4, height: 5)])

        let report = try #require(session.events.report(of: 1))
        #expect(report.source == .translated && report.patches == 1 && report.patchFileBytes > 0)
        #expect(report.text?.blocksFound == 2 && report.text?.blocksRead == 1)
        #expect(report.imageWidth == 41 && report.drawing != nil)
    }

    @Test func aPageWithNothingToTranslateIsDoneWithoutDrawing() async throws {
        let world = try await TranslationWorld()
        world.set { $0.pagesWithoutText = [1] }
        let service = world.service()
        let session = await service.open()

        await service.show(session, onScreen: [1])
        try await eventually("page 1 to be done") { session.events.status(of: 1) == .nothingToDraw }

        #expect(world.log == ["text 1"])
        // Its row is kept, so the page is never found and read again.
        #expect(try await world.storedText(of: 1)?.regions.map(\.kind) == [.soundEffect])
        #expect(!world.hasPatchFile(of: 1))
    }

    // MARK: The cache

    @Test func aStoredPageWithItsPatchFileIsShownWithNoModelNoFetchAndNoDrawing() async throws {
        let world = try await TranslationWorld()
        await world.writer.add(TranslationWorld.storedPage(1))
        let patch = Patch(rect: PixelRect(x: 1, y: 1, width: 2, height: 2), pixels: Data(repeating: 255, count: 16))
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        _ = try await PatchFile.write([patch], imageWidth: 41, imageHeight: 64, colorSpace: space, to: world.patchFile(of: 1))
        let service = world.service()
        let session = await service.open()

        await service.show(session, onScreen: [1])
        try await eventually("page 1 to be shown") { session.events.isTranslated(1) }

        // Reported straight away, without "translating" in between.
        #expect(session.events.statuses(of: 1).count == 1)
        #expect(session.events.report(of: 1)?.source == .stored)
        #expect(world.pipelineLoads.isEmpty && world.log.isEmpty && world.fetches(of: 1) == 0)
        #expect(world.value(\.inpainterLoads) == 0)
    }

    /// A promise of the cache: a stored page whose patch file is gone is drawn again
    /// from its text, and no detector, reader or translator is loaded for it.
    @Test func aStoredPageWithoutItsPatchFileIsDrawnAgainWithNoModelLoaded() async throws {
        let world = try await TranslationWorld()
        await world.writer.add(TranslationWorld.storedPage(1))
        await world.writer.flush()
        await world.writer.waitUntilWritten()
        let service = world.service()
        let session = await service.open()

        await service.show(session, onScreen: [1])
        try await eventually("page 1 to be drawn again") { session.events.isTranslated(1) }
        try await settled(service)

        #expect(session.events.statuses(of: 1).first == .translating && session.events.statuses(of: 1).count == 2)
        #expect(world.pipelineLoads.isEmpty)
        if case .unloaded = await service.pipelineState {} else { Issue.record("a model was loaded for a stored page") }
        #expect(world.log == ["draw 1"])
        #expect(world.fetches(of: 1) == 1 && world.hasPatchFile(of: 1))
        let report = try #require(session.events.report(of: 1))
        #expect(report.source == .redrawn && report.text == nil && report.patches == 1)
    }

    @Test func aStoredPageWithNothingToDrawIsDoneAtOnce() async throws {
        let world = try await TranslationWorld()
        await world.writer.add(TranslationWorld.storedPage(1, translated: false))
        let service = world.service()
        let session = await service.open()

        await service.show(session, onScreen: [1])
        try await eventually("page 1 to be done") { session.events.status(of: 1) == .nothingToDraw }

        #expect(world.log.isEmpty && world.fetches(of: 1) == 0 && world.pipelineLoads.isEmpty)
    }

    @Test func aGalleryReadAgainShowsItsPagesBeforeAnyModelHasLoaded() async throws {
        let world = try await TranslationWorld()
        let first = world.service()
        let reader = await first.open()
        await first.show(reader, onScreen: [1], ahead: [2])
        try await eventually("both pages to be translated") { reader.events.isTranslated(1) && reader.events.isTranslated(2) }
        await first.perform(.close(reader.id))
        let loads = world.pipelineLoads.count, log = world.log

        // Another process, later: the same database and the same cache folder.
        let second = world.service()
        let again = await second.open()
        await second.show(again, onScreen: [1], ahead: [2, 3])
        try await eventually("the stored pages to be shown") { again.events.isTranslated(1) && again.events.isTranslated(2) }

        #expect(again.events.statuses(of: 1).count == 1 && again.events.statuses(of: 2).count == 1)
        // Only the page that is new costs anything.
        try await eventually("page 3 to be translated") { again.events.isTranslated(3) }
        #expect(world.pipelineLoads.count == loads + 1)
        #expect(Array(world.log.dropFirst(log.count)) == ["text 3", "draw 3"])
    }

    @Test func theFirstUseInAProcessExpiresTheCacheAndPreparesOnce() async throws {
        let world = try await TranslationWorld()
        let other = PageTranslationModelSet(detector: .v4s)
        await world.writer.add(TranslationWorld.storedPage(1, modelSet: other))
        await world.writer.add(TranslationWorld.storedPage(2))
        await world.writer.flush()
        await world.writer.waitUntilWritten()
        let stale = world.patchFile(
            of: 1, variant: PageTranslationPatchVariant(modelSet: other, repaint: .off, renderVersion: 1)
        )
        try FileManager.default.createDirectory(at: stale.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("old".utf8).write(to: stale)
        let service = world.service()

        let first = await service.open()
        _ = await service.open()
        await world.writer.waitUntilWritten()

        // Rows and patch files of other models go; those of the current models stay.
        #expect(try await world.database.pageTranslationCount(gid: Self.gid, modelSetKey: other.key) == 0)
        #expect(try await world.database.translatedPageIndices(gid: Self.gid, modelSetKey: Self.key) == [2])
        #expect(!FileManager.default.fileExists(atPath: stale.path))
        #expect(world.value(\.prepares) == 1)
        await service.perform(.close(first.id))
    }

    // MARK: Without models

    @Test func withoutAModelSetEveryPageFails() async throws {
        let world = try await TranslationWorld(setup: nil)
        let service = world.service()
        let session = await service.open()

        await service.show(session, onScreen: [1])

        try await eventually("page 1 to fail") { session.events.status(of: 1) == .failed(.modelsMissing) }
        #expect(world.pipelineLoads.isEmpty && world.fetches(of: 1) == 0)
    }

    @Test func withModelsNotInstalledStoredPagesStillShowAndNewOnesFail() async throws {
        let world = try await TranslationWorld(setup: TranslationWorld.setup(installed: false))
        await world.writer.add(TranslationWorld.storedPage(1))
        let service = world.service()
        let session = await service.open()

        await service.show(session, onScreen: [1], ahead: [2])
        try await eventually("page 1 to be drawn from its text") { session.events.isTranslated(1) }
        try await eventually("page 2 to fail") { session.events.status(of: 2) == .failed(.modelsMissing) }

        #expect(world.pipelineLoads.isEmpty && world.log == ["draw 1"])
    }
}
