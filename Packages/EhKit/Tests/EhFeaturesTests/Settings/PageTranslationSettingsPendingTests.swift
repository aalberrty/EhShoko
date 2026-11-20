import EhCore
import EhFeatures
import EhModels
import Foundation
import Testing

/// A pending choice kept in the settings, so it survives the app being closed before its
/// install ends.
@Suite struct PageTranslationSettingsPendingTests {
    // MARK: Kept and cleared with `pending`

    @Test func aPendingChoiceIsKeptUntilItsInstallAppliesIt() async throws {
        let harness = TranslationStoreHarness()
        try await harness.installDefaultSet()
        harness.hold(.galTransl4B)
        let model = harness.makeModel()
        await model.load()

        await model.choose(.translator(.galTransl4B))

        #expect(harness.settings.pageTranslationPendingTranslator == .galTransl4B)
        #expect(harness.settings.pageTranslationPendingDetector == nil)
        harness.release(.galTransl4B)
        await waitFor("the language model is chosen") { harness.settings.pageTranslationTranslator == .galTransl4B }
        #expect(harness.settings.pageTranslationPendingTranslator == nil)
    }

    @Test func choosingTheCurrentModelAgainForgetsTheKeptChoice() async throws {
        let harness = TranslationStoreHarness()
        try await harness.installDefaultSet()
        harness.hold(.galTransl4B)
        let model = harness.makeModel()
        await model.load()
        await model.choose(.translator(.galTransl4B))

        await model.choose(.translator(.jmtFast1))

        #expect(harness.settings.pageTranslationPendingTranslator == nil)
    }

    @Test func choosingAnotherMissingModelReplacesTheKeptChoice() async throws {
        let harness = TranslationStoreHarness()
        try await harness.installDefaultSet()
        harness.hold(.v4s)
        harness.hold(.yolo26s)
        let model = harness.makeModel()
        await model.load()
        await model.choose(.detector(.v4s))
        #expect(harness.settings.pageTranslationPendingDetector == .v4s)

        await model.choose(.detector(.yolo26s))

        #expect(harness.settings.pageTranslationPendingDetector == .yolo26s)
        await model.choose(.detector(.k2xl))
        #expect(harness.settings.pageTranslationPendingDetector == nil)
    }

    @Test func aDownloadThatEndsWithoutAnInstallForgetsTheKeptChoice() async throws {
        let harness = TranslationStoreHarness()
        try await harness.installDefaultSet()
        harness.hold(.galTransl4B)
        let model = harness.makeModel()
        await model.load()
        await model.choose(.translator(.galTransl4B))
        await waitFor("the language model is being fetched") { harness.isWaiting(.galTransl4B) }

        // Delete All, or anything else that stops it, ends the download without an install.
        await harness.store.delete([.galTransl4B])

        await waitFor("the choice is given up") { model.pending.isEmpty }
        #expect(harness.settings.pageTranslationPendingTranslator == nil)
        #expect(harness.settings.pageTranslationTranslator == .jmtFast1)
    }

    // MARK: A model created afresh on a kept choice

    @Test func aKeptChoiceWhoseModelWasInstalledMeanwhileApplies() async throws {
        let harness = TranslationStoreHarness()
        try harness.copyIn([.v4s])
        try await harness.installDefaultSet()
        harness.settings.pageTranslationPendingDetector = .v4s

        let model = harness.makeModel()
        await model.load()

        #expect(harness.settings.pageTranslationDetector == .v4s)
        #expect(harness.settings.pageTranslationPendingDetector == nil)
        #expect(model.pending.isEmpty)
    }

    @Test func aKeptChoiceStillDownloadingIsWaitedFor() async throws {
        let harness = TranslationStoreHarness()
        try await harness.installDefaultSet()
        harness.hold(.yolo26s)
        // The store goes on with what was asked for before the app was closed.
        harness.store.download([.yolo26s])
        await waitFor("the detector is being fetched") { harness.isWaiting(.yolo26s) }
        harness.settings.pageTranslationPendingDetector = .yolo26s

        let model = harness.makeModel()
        await model.load()

        #expect(model.pending[.detector] == .detector(.yolo26s))
        #expect(harness.settings.pageTranslationDetector == .k2xl)
        #expect(harness.settings.pageTranslationPendingDetector == .yolo26s)
        harness.release(.yolo26s)
        await waitFor("the detector is chosen") { harness.settings.pageTranslationDetector == .yolo26s }
        #expect(harness.settings.pageTranslationPendingDetector == nil)
    }

    @Test func aKeptChoiceWhoseDownloadEndedIsForgotten() async throws {
        let harness = TranslationStoreHarness()
        try await harness.installDefaultSet()
        harness.settings.pageTranslationPendingTranslator = .galTransl4B

        let model = harness.makeModel()
        await model.load()

        #expect(model.pending.isEmpty)
        #expect(harness.settings.pageTranslationPendingTranslator == nil)
        #expect(harness.settings.pageTranslationTranslator == .jmtFast1)
        #expect(harness.store.state(of: .galTransl4B) == .missing)
    }

    @Test func aKeptChoiceThatIsAlreadyCurrentIsForgotten() async throws {
        let harness = TranslationStoreHarness()
        try await harness.installDefaultSet()
        harness.settings.pageTranslationPendingReader = .cpt2

        let model = harness.makeModel()
        await model.load()

        #expect(model.pending.isEmpty)
        #expect(harness.settings.pageTranslationPendingReader == nil)
    }

    @Test func aChoiceMadeBeforeLoadingKeepsTheOtherKindsKeptChoice() async throws {
        let harness = TranslationStoreHarness()
        try harness.copyIn([.v4s])
        try await harness.installDefaultSet()
        harness.hold(.galTransl4B)
        harness.settings.pageTranslationPendingDetector = .v4s
        let model = harness.makeModel()

        await model.choose(.translator(.galTransl4B))
        #expect(harness.settings.pageTranslationPendingDetector == .v4s)
        await model.load()

        #expect(harness.settings.pageTranslationDetector == .v4s)
        #expect(harness.settings.pageTranslationPendingDetector == nil)
        #expect(harness.settings.pageTranslationPendingTranslator == .galTransl4B)
    }
}
