import EhModels
import Foundation
import Testing
@testable import EhCore

/// The store from the outside: what the screens see while models are downloaded,
/// installed, paused, cancelled and deleted. Transport and compiler are stubs.
@MainActor
@Suite struct PageTranslationModelStoreTests {
    private let defaultSet: [ModelArtifactID] = [.k2xl, .cpt2, .jmtFast1, .lamaManga]

    private var defaultSetBytes: Int64 {
        defaultSet.reduce(0) { $0 + StoreSamples.artifact($1).downloadSize }
    }

    // MARK: Downloading

    @Test func theDefaultSetIsDownloadedAndInstalled() async throws {
        let harness = StoreHarness()
        harness.publishDefaultSet()
        let store = harness.store
        await store.refresh()
        #expect(store.isLoaded)
        #expect(store.requiredArtifacts == defaultSet)
        #expect(store.requiredModelsState == .missing(bytes: defaultSetBytes))
        #expect(store.bytesToDownload(for: defaultSet) == defaultSetBytes)

        store.downloadRequiredModels()
        #expect(defaultSet.allSatisfy { store.state(of: $0) == .waiting })
        await store.waitUntilIdle()

        #expect(defaultSet.allSatisfy { store.state(of: $0) == .installed })
        #expect(store.requiredModelsState == .ready)
        #expect(store.state(of: .v4s) == .missing)
        // The repaint model is part of the default download.
        #expect(store.installedFiles(of: .lamaManga) != nil)
        #expect(harness.compiler.compiled.sorted() == [
            "Decoder.mlpackage", "Encoder.mlpackage", "K2XL.mlpackage", "LaMa.mlpackage", "decoder.mlpackage"
        ])
        #expect(harness.compiler.prepared.count == 5)
        #expect(harness.files(in: .cpt2) == [
            "CREDITS.md", "Decoder.mlmodelc/weights.bin", "Encoder.mlmodelc/weights.bin", "LICENSE", "installed.json",
            "vocab.txt"
        ])
        #expect(!FileManager.default.fileExists(atPath: harness.root.appending(path: "downloads.json").path(percentEncoded: false)))
        #expect(store.bytesToDownload(for: defaultSet) == 0)
        #expect(store.installedBytes == defaultSet.reduce(0) { $0 + store.installedBytes(of: $1) })
        #expect(store.installedBytes(of: .k2xl) == 5300 + 400 + 120)
    }

    /// The token goes to the private store's host and to no other.
    @Test func theTokenIsNeverSentToAnotherHost() async throws {
        let harness = StoreHarness(publicStore: StoreSamples.publicStore)
        harness.publishDefaultSet()
        harness.publish(.v4s, at: StoreSamples.publicStore)
        let store = harness.store
        await store.refresh()

        store.download(defaultSet + [.v4s])
        await store.waitUntilIdle()

        #expect(store.state(of: .v4s) == .installed)
        let requests = harness.transport.requests
        #expect(!requests.isEmpty)
        for request in requests {
            let isPrivate = request.url.host() == StoreSamples.privateStore.host()
            #expect(request.token == (isPrivate ? StoreSamples.token : nil), "\(request.url)")
        }
        // Each kind of source was really asked.
        #expect(!harness.transport.requests(to: "author.example").isEmpty)
        #expect(!harness.transport.requests(to: "public.example").isEmpty)
        #expect(!harness.transport.requests(to: "private.example").isEmpty)
        #expect(harness.transport.mainThreadCalls == 0)
        #expect(harness.compiler.mainThreadCalls == 0)
    }

    @Test func aStoreWithoutATokenSendsNone() async throws {
        let harness = StoreHarness()
        try harness.tokens.write(nil)
        harness.publish(.v4s, at: StoreSamples.privateStore)
        let store = harness.store
        await store.refresh()
        #expect(!store.hasSourceToken)

        store.download([.v4s])
        await store.waitUntilIdle()

        #expect(store.state(of: .v4s) == .installed)
        #expect(harness.transport.requests.allSatisfy { $0.token == nil })
    }

    /// The author's own address comes first and the private store is asked when it fails.
    @Test func aFileItsAuthorNoLongerOffersComesFromTheNextSource() async throws {
        let harness = StoreHarness()
        harness.publish(.jmtFast1, atPublisher: StoreSamples.mirror)
        let store = harness.store
        await store.refresh()

        store.download([.jmtFast1])
        await store.waitUntilIdle()

        #expect(store.state(of: .jmtFast1) == .installed)
        #expect(!harness.transport.requests(to: "author.example").isEmpty)
        #expect(!harness.transport.requests(to: "mirror.example").isEmpty)
        #expect(harness.transport.requests(to: "private.example").isEmpty)
    }

    /// The licence and the credits are files of the artifact and are kept beside it.
    @Test func theLicenceFilesArriveWithAnArtifact() async throws {
        let harness = StoreHarness()
        harness.publish(.v4s, at: StoreSamples.privateStore)
        let store = harness.store
        await store.refresh()

        store.download([.v4s])
        await store.waitUntilIdle()

        let files = try #require(store.installedFiles(of: .v4s))
        #expect(try Data(contentsOf: files.file("LICENSE")) == StoreSamples.data("LICENSE", of: .v4s))
        #expect(try Data(contentsOf: files.file("CREDITS.md")) == StoreSamples.data("CREDITS.md", of: .v4s))
        #expect(files.compiledModel(ofPackage: "V4S.mlpackage").lastPathComponent == "V4S.mlmodelc")
        #expect(files.artifact.credit.name == "Detector B")
        #expect(files.isPrepared)
    }

    @Test func aLanguageModelIsInstalledWithoutCompilingOrPreparing() async throws {
        let harness = StoreHarness()
        harness.publish(.galTransl4B, at: StoreSamples.privateStore)
        let store = harness.store
        await store.refresh()

        store.download([.galTransl4B])
        await store.waitUntilIdle()

        #expect(store.state(of: .galTransl4B) == .installed)
        #expect(harness.compiler.compiled.isEmpty && harness.compiler.prepared.isEmpty)
        #expect(harness.files(in: .galTransl4B) == ["CREDITS.md", "LICENSE", "installed.json", "model.gguf"])
        // Eleven ranges for the model, one each for the two notices.
        #expect(harness.transport.requests.count == 13)
    }

    // MARK: Failing

    @Test func aDownloadThatDoesNotFitDoesNotStart() async throws {
        let harness = StoreHarness()
        harness.publishDefaultSet()
        let needed = ModelStoreEnvironment.spaceNeeded(forDownloading: defaultSetBytes)
        harness.freeSpace.set(needed - 1)
        let store = harness.store
        await store.refresh()

        store.downloadRequiredModels()
        await store.waitUntilIdle()

        let failure = ModelStoreFailure.noSpace(needed: needed, available: needed - 1)
        #expect(defaultSet.allSatisfy { store.state(of: $0) == .failed(failure) })
        #expect(store.requiredModelsState == .failed(failure))
        #expect(harness.transport.requests.isEmpty)

        // With one more byte it goes through.
        harness.freeSpace.set(needed)
        store.downloadRequiredModels()
        await store.waitUntilIdle()
        #expect(store.requiredModelsState == .ready)
    }

    /// One and a half times the download plus 200 MB.
    @Test func theRoomADownloadNeeds() {
        #expect(ModelStoreEnvironment.spaceNeeded(forDownloading: 1_000_000_000) == 1_700_000_000)
        #expect(ModelStoreEnvironment.spaceNeeded(forDownloading: 0) == 200_000_000)
    }

    @Test func aFileNoSourceHasFailsAndCanBeTriedAgain() async throws {
        let harness = StoreHarness()
        let store = harness.store
        await store.refresh()

        store.download([.v4s])
        await store.waitUntilIdle()
        #expect(store.state(of: .v4s) == .failed(.refused(status: 404)))
        #expect(harness.logs.get().contains { $0.contains("det-v4s stopped") })

        harness.publish(.v4s, at: StoreSamples.privateStore)
        store.download([.v4s])
        await store.waitUntilIdle()
        #expect(store.state(of: .v4s) == .installed)
    }

    @Test func aWrongChecksumAtEverySourceStopsWithAMessage() async throws {
        let harness = StoreHarness()
        harness.publish(.v4s, at: StoreSamples.privateStore, corrupting: ["V4S.mlpackage/Data/com.apple.CoreML/weights/weight.bin"])
        let store = harness.store
        await store.refresh()

        store.download([.v4s])
        await store.waitUntilIdle()

        #expect(store.state(of: .v4s) == .failed(.checksumMismatch))
        #expect(harness.compiler.compiled.isEmpty)
        #expect(!harness.exists("V4S.mlpackage/Data/com.apple.CoreML/weights/weight.bin", in: .v4s))
    }

    @Test func anArtifactNoSourceOffersCannotBeDownloaded() async throws {
        let harness = StoreHarness(privateStore: false)
        let store = harness.store
        await store.refresh()

        store.download([.k2xl])
        await store.waitUntilIdle()

        #expect(store.state(of: .k2xl) == .failed(.noSource))
        #expect(harness.transport.requests.isEmpty)
    }

    @Test func aPackageThatDoesNotCompileIsAFailedInstall() async throws {
        let harness = StoreHarness()
        harness.publish(.v4s, at: StoreSamples.privateStore)
        harness.compiler.failCompiling(CocoaError(.fileReadCorruptFile))
        let store = harness.store
        await store.refresh()

        store.download([.v4s])
        await store.waitUntilIdle()

        #expect(store.state(of: .v4s) == .failed(.installFailed))
        #expect(store.installedFiles(of: .v4s) == nil)
    }

    @Test func aFirstLoadThatFailsStillLeavesTheModelInstalled() async throws {
        let harness = StoreHarness()
        harness.publish(.v4s, at: StoreSamples.privateStore)
        harness.compiler.failPreparing(CocoaError(.fileReadUnknown))
        let store = harness.store
        await store.refresh()

        store.download([.v4s])
        await store.waitUntilIdle()

        #expect(store.state(of: .v4s) == .installed)
        #expect(store.installedFiles(of: .v4s)?.isPrepared == false)
    }
}
