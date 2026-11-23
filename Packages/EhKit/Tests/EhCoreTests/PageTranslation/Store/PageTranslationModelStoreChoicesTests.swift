import EhModels
import Foundation
import Observation
import Testing
@testable import EhCore

/// Which models the choices of the settings mean for a user, given what their sources
/// offer: the default is resolved to the best model they can have.
@MainActor
@Suite struct PageTranslationModelStoreChoicesTests {
    // MARK: The owner

    @Test func withAPrivateStoreTheChoicesAreTakenAsTheyAre() async {
        let harness = StoreHarness()
        let store = harness.store
        await store.refresh()

        #expect(store.privateStoreAddress == StoreSamples.privateStore)
        #expect(store.resolvedDetector == .k2xl)
        #expect(store.resolvedModelSet == .default)
        #expect(store.resolvedRepaint == .lamaManga)
        #expect(store.requiredArtifacts == [.k2xl, .cpt2, .jmtFast1, .lamaManga])
        #expect(StoreSamples.catalog.artifacts.allSatisfy { store.isAvailable($0.id) })
        #expect(store.requiredModelsIncludeNonCommercial)
    }

    // MARK: Everyone else

    /// Without a private store the default detector is the best one a public store may
    /// hold; the setting itself is not touched.
    @Test func withAPublicStoreTheDefaultDetectorIsTheOneEveryoneMayHave() async {
        let harness = StoreHarness(privateStore: false, publicStore: StoreSamples.publicStore)
        let store = harness.store
        await store.refresh()

        #expect(harness.settings.modelSet.detector == .k2xl)
        #expect(store.resolvedDetector == .v4s)
        #expect(store.resolvedModelSet == PageTranslationModelSet(detector: .v4s, reader: .cpt2, translator: .jmtFast1))
        #expect(store.requiredArtifacts == [.v4s, .cpt2, .jmtFast1, .lamaManga])
        #expect(!store.isAvailable(.k2xl))
        #expect(store.isAvailable(.v4s))
        #expect(store.requiredModelsState == .missing(bytes: [ModelArtifactID.v4s, .cpt2, .jmtFast1, .lamaManga]
            .reduce(0) { $0 + StoreSamples.artifact($1).downloadSize }))
    }

    @Test func thePublicSetDownloadsWithNoTokenAndNothingToSetUp() async {
        let harness = StoreHarness(privateStore: false, publicStore: StoreSamples.publicStore)
        for id in [ModelArtifactID.v4s, .cpt2, .lamaManga] { harness.publish(id, at: StoreSamples.publicStore) }
        harness.publish(.jmtFast1, atPublisher: StoreSamples.publisher)
        let store = harness.store
        await store.refresh()

        store.downloadRequiredModels()
        await store.waitUntilIdle()

        #expect(store.requiredModelsState == .ready)
        #expect(harness.transport.requests.allSatisfy { $0.token == nil })
        #expect(harness.transport.requests(to: "private.example").isEmpty)
    }

    /// Until a public store exists, someone without a private one has no detector at all:
    /// the screens say a source is needed.
    @Test func withNoStoreAtAllASourceIsNeeded() async {
        let harness = StoreHarness(privateStore: false)
        let store = harness.store
        await store.refresh()

        #expect(store.privateStoreAddress == nil)
        #expect(store.resolvedDetector == nil)
        #expect(store.resolvedReader == nil)
        // The translator comes from its author, whatever stores there are.
        #expect(store.resolvedTranslator == .jmtFast1)
        #expect(store.resolvedModelSet == nil)
        #expect(store.resolvedRepaint == .off)
        #expect(store.requiredModelsState == .unavailable)
        #expect(store.requiredArtifacts == [.jmtFast1])
    }

    /// The better detector is theirs from the moment their own copy is on the device.
    @Test func aModelThatIsInstalledCanBeChosenWhateverTheSourcesOffer() async throws {
        let harness = StoreHarness(privateStore: false, publicStore: StoreSamples.publicStore)
        try harness.copyIn(.k2xl)
        let store = harness.store
        #expect(store.resolvedDetector == .v4s)

        await store.refresh()
        await store.waitUntilIdle()

        #expect(store.isAvailable(.k2xl))
        #expect(store.resolvedDetector == .k2xl)
        #expect(store.requiredArtifacts.first == .k2xl)
    }

    // MARK: Choices

    @Test func aChosenModelIsKeptWhenItCanBeHad() async {
        let harness = StoreHarness(privateStore: false, publicStore: StoreSamples.publicStore)
        harness.settings.modelSet = PageTranslationModelSet(detector: .v4s, reader: .cpt2, translator: .galTransl4B)
        harness.settings.repaint = .off
        let store = harness.store
        await store.refresh()

        #expect(store.resolvedModelSet == harness.settings.modelSet)
        #expect(store.resolvedRepaint == .off)
        #expect(store.requiredArtifacts == [.v4s, .cpt2, .galTransl4B])
    }

    /// The switch for sound effects is part of the resolved set, so the reader's count of
    /// pages translated before and the service's setup both follow it. With a detector that
    /// has no sound-effect class it names nothing.
    @Test func theResolvedSetCarriesTheSwitchForSoundEffects() async {
        let harness = StoreHarness()
        harness.settings.modelSet = PageTranslationModelSet(translatesSoundEffects: true)
        let store = harness.store
        await store.refresh()
        #expect(store.resolvedModelSet == PageTranslationModelSet(translatesSoundEffects: true))
        #expect(store.resolvedModelSet?.key == "k2xl768.cpt2.jmt1.t1.sfx")
        #expect(store.requiredArtifacts == [.k2xl, .cpt2, .jmtFast1, .lamaManga])

        let everyone = StoreHarness(privateStore: false, publicStore: StoreSamples.publicStore)
        everyone.settings.modelSet = PageTranslationModelSet(translatesSoundEffects: true)
        await everyone.store.refresh()
        #expect(everyone.store.resolvedModelSet?.detector == .v4s)
        #expect(everyone.store.resolvedModelSet?.key == PageTranslationModelSet(detector: .v4s).key)
    }

    /// A translator is offered once it has an entry in the catalog. Until then a choice
    /// of it falls back to the first translator that has one.
    @Test func aChoiceWithoutACatalogEntryFallsBack() async {
        let harness = StoreHarness()
        harness.settings.modelSet.translator = .sakura1_5B
        harness.settings.modelSet.reader = .narSmall
        harness.settings.repaint = .bigLama
        let store = harness.store
        await store.refresh()

        #expect(!store.isAvailable(.sakura1_5B))
        #expect(store.resolvedTranslator == .jmtFast1)
        #expect(store.resolvedReader == .cpt2)
        #expect(store.resolvedRepaint == .lamaManga)
    }

    @Test func aPrivateStoreAddressThatIsNotOneCountsAsNone() async {
        let harness = StoreHarness(privateStore: false)
        harness.settings.sourceAddress = "not an address"
        let store = harness.store
        await store.refresh()

        #expect(store.privateStoreAddress == nil)
        #expect(store.resolvedDetector == nil)

        harness.settings.sourceAddress = "  https://huggingface.co/someone/models/resolve/main/ "
        #expect(store.privateStoreAddress?.absoluteString == "https://huggingface.co/someone/models/resolve/main")
        #expect(store.resolvedDetector == .k2xl)
    }

    // MARK: Where the set stands

    @Test func theSetShowsItsDownloadAsOneProgress() async {
        let harness = StoreHarness()
        harness.publishDefaultSet()
        harness.transport.hang(harness.address(of: "LaMa.mlpackage/Data/com.apple.CoreML/weights/weight.bin", in: .lamaManga))
        let store = harness.store
        await store.refresh()
        let total = [ModelArtifactID.k2xl, .cpt2, .jmtFast1, .lamaManga].reduce(Int64(0)) {
            $0 + StoreSamples.artifact($1).downloadSize
        }

        store.downloadRequiredModels()
        await waitUntil("three of the four models are installed") {
            [ModelArtifactID.k2xl, .cpt2, .jmtFast1].allSatisfy { store.state(of: $0) == .installed }
        }
        await waitUntil("everything but the held file has arrived") {
            store.requiredModelsState == .downloading(ModelTransferProgress(completedBytes: total - 2048, totalBytes: total))
        }

        harness.transport.release(harness.address(of: "LaMa.mlpackage/Data/com.apple.CoreML/weights/weight.bin", in: .lamaManga))
        store.cancelDownloads()
        await store.waitUntilIdle()
        // Three are installed and the fourth's whole files stay on disk.
        #expect(store.requiredModelsState == .missing(bytes: 2048))
    }

    @Test func theSetIsPreparingWhileModelsAreCheckedAndCompiled() async throws {
        let harness = StoreHarness()
        for id in [ModelArtifactID.k2xl, .cpt2, .jmtFast1, .lamaManga] { try harness.copyIn(id) }
        let compiling = harness.compiler.holdCompiling()
        let store = harness.store

        await store.refresh()
        await waitUntil("a package is being compiled") { !harness.compiler.compiled.isEmpty }
        #expect(store.requiredModelsState == .preparing)
        compiling.finish()
        await store.waitUntilIdle()

        #expect(store.requiredModelsState == .ready)
        #expect(harness.transport.requests.isEmpty)
    }

    /// A screen that shows the set is told when it changes, and by nothing else.
    @Test func theSetsStateIsObservable() async {
        let harness = StoreHarness()
        harness.publishDefaultSet()
        let store = harness.store
        await store.refresh()
        let changed = Shared(false)
        withObservationTracking {
            _ = store.requiredModelsState
        } onChange: {
            changed.set(true)
        }
        #expect(!changed.get())

        store.downloadRequiredModels()

        #expect(changed.get())
        await store.waitUntilIdle()
    }
}
