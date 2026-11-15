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

    // MARK: Pausing, going on, cancelling

    @Test func aPausedDownloadKeepsWhatArrivedAndGoesOn() async throws {
        let harness = StoreHarness()
        harness.publish(.galTransl4B, at: StoreSamples.privateStore)
        let model = harness.address(of: "model.gguf", in: .galTransl4B)
        harness.transport.hang(model, from: 5 * 1024)
        let store = harness.store
        await store.refresh()
        store.download([.galTransl4B])
        await waitUntil("five ranges are on disk") {
            if case .downloading(let progress) = store.state(of: .galTransl4B) { progress.completedBytes >= 5 * 1024 + 520 } else { false }
        }

        store.pause()
        await store.waitUntilIdle()

        #expect(store.isPaused)
        guard case .paused(let paused) = store.state(of: .galTransl4B) else {
            Issue.record("Expected paused, got \(store.state(of: .galTransl4B))")
            return
        }
        #expect(paused.totalBytes == 11_020)
        #expect(paused.completedBytes >= 5 * 1024 + 520)
        // The two notices are whole, so the set shows them and the five ranges.
        harness.settings.modelSet.translator = .galTransl4B
        if case .paused = store.requiredModelsState {} else { Issue.record("\(store.requiredModelsState)") }

        harness.transport.release(model)
        harness.transport.clearRequests()
        store.resume()
        #expect(!store.isPaused)
        await store.waitUntilIdle()

        #expect(store.state(of: .galTransl4B) == .installed)
        // Only the ranges that had not arrived were asked for again.
        #expect(harness.transport.requests.map(\.range.lowerBound).sorted() == (5...10).map { Int64($0) * 1024 })
    }

    /// Going on does not have to wait until the paused work has wound down.
    @Test func pausingAndGoingOnAtOnceStillFinishes() async throws {
        let harness = StoreHarness()
        harness.publish(.galTransl4B, at: StoreSamples.privateStore)
        let model = harness.address(of: "model.gguf", in: .galTransl4B)
        harness.transport.hang(model, from: 4 * 1024)
        let store = harness.store
        await store.refresh()
        store.download([.galTransl4B])
        await waitUntil("four ranges are on disk") {
            if case .downloading(let progress) = store.state(of: .galTransl4B) { progress.completedBytes >= 4 * 1024 + 520 } else { false }
        }

        store.pause()
        harness.transport.release(model)
        store.resume()
        await store.waitUntilIdle()

        #expect(store.state(of: .galTransl4B) == .installed)
        #expect(!store.isPaused)
        #expect(try Data(contentsOf: harness.layout.url(ofPath: "model.gguf", in: .galTransl4B))
            == StoreSamples.data("model.gguf", of: .galTransl4B))
    }

    @Test func cancellingDeletesWhatADownloadLeft() async throws {
        let harness = StoreHarness()
        harness.publish(.galTransl4B, at: StoreSamples.privateStore)
        harness.transport.hang(harness.address(of: "model.gguf", in: .galTransl4B), from: 3 * 1024)
        let store = harness.store
        await store.refresh()
        store.download([.galTransl4B])
        await waitUntil("three ranges are on disk") {
            if case .downloading(let progress) = store.state(of: .galTransl4B) { progress.completedBytes >= 3 * 1024 + 520 } else { false }
        }

        store.cancelDownloads()
        await store.waitUntilIdle()

        #expect(store.state(of: .galTransl4B) == .missing)
        #expect(!store.isPaused)
        // Whole files stay; the part file and the waiting ranges are gone.
        #expect(harness.files(in: .galTransl4B) == ["CREDITS.md", "LICENSE"])
        #expect(store.bytesToDownload(for: [.galTransl4B]) == 10_500)
        #expect(!FileManager.default.fileExists(atPath: harness.root.appending(path: "downloads.json").path(percentEncoded: false)))
    }

    /// The app is closed in the middle of a download and started again: the new store
    /// goes on by itself and fetches no range a second time.
    @Test func aDownloadGoesOnAfterTheAppWasClosed() async throws {
        let harness = StoreHarness()
        harness.publish(.galTransl4B, at: StoreSamples.privateStore)
        let model = harness.address(of: "model.gguf", in: .galTransl4B)
        harness.transport.hang(model, from: 6 * 1024)
        let first = harness.store
        await first.refresh()
        first.download([.galTransl4B])
        await waitUntil("six ranges are on disk") {
            if case .downloading(let progress) = first.state(of: .galTransl4B) { progress.completedBytes >= 6 * 1024 + 520 } else { false }
        }
        await first.intentWrite?.value
        // The first store's process is gone; its requests die with it.
        for task in first.tasks.values { task.cancel() }
        await first.waitUntilIdle()
        harness.transport.release(model)
        harness.transport.clearRequests()

        let second = harness.makeStore()
        #expect(second.state(of: .galTransl4B) == .missing)
        await second.refresh()
        await second.waitUntilIdle()

        #expect(second.state(of: .galTransl4B) == .installed)
        #expect(harness.transport.requests.map(\.range.lowerBound).sorted() == (6...10).map { Int64($0) * 1024 })
        #expect(harness.transport.collected >= 1)
        #expect(try Data(contentsOf: harness.layout.url(ofPath: "model.gguf", in: .galTransl4B))
            == StoreSamples.data("model.gguf", of: .galTransl4B))
    }

    @Test func aPausedDownloadStaysPausedAfterTheAppWasClosed() async throws {
        let harness = StoreHarness()
        harness.publish(.galTransl4B, at: StoreSamples.privateStore)
        harness.transport.hang(harness.address(of: "model.gguf", in: .galTransl4B), from: 2 * 1024)
        let first = harness.store
        await first.refresh()
        first.download([.galTransl4B])
        await waitUntil("two ranges are on disk") {
            if case .downloading(let progress) = first.state(of: .galTransl4B) { progress.completedBytes >= 2 * 1024 + 520 } else { false }
        }
        first.pause()
        await first.waitUntilIdle()
        harness.transport.clearRequests()

        let second = harness.makeStore()
        await second.refresh()
        await second.waitUntilIdle()

        #expect(second.isPaused)
        #expect(second.state(of: .galTransl4B) == .paused(ModelTransferProgress(completedBytes: 2 * 1024 + 520, totalBytes: 11_020)))
        #expect(harness.transport.requests.isEmpty)
    }

    // MARK: Files that are already there

    /// Models copied in from a Mac are checked and adopted with no download.
    @Test func filesCopiedInAreAdopted() async throws {
        let harness = StoreHarness(privateStore: false)
        try harness.copyIn(.k2xl)
        let store = harness.store

        await store.refresh()
        await store.waitUntilIdle()

        #expect(store.state(of: .k2xl) == .installed)
        #expect(harness.compiler.compiled == ["K2XL.mlpackage"])
        #expect(harness.transport.requests.isEmpty)
        #expect(store.uncheckedCopies.isEmpty)
        // A second look changes nothing and compiles nothing.
        await store.refresh()
        await store.waitUntilIdle()
        #expect(harness.compiler.compiled.count == 1)
    }

    /// A copy that cannot be checked is refused, for every artifact.
    @Test(arguments: [ModelArtifactID.k2xl, .v4s, .galTransl4B])
    func aCopyThatDoesNotMatchIsNotUsed(id: ModelArtifactID) async throws {
        let harness = StoreHarness()
        let path = StoreSamples.contents[id]![0].path
        try harness.copyIn(id, corrupting: [path])
        let store = harness.store

        await store.refresh()
        await store.waitUntilIdle()

        #expect(store.state(of: id) == .missing)
        #expect(store.uncheckedCopies == [id])
        #expect(store.installedFiles(of: id) == nil)
        #expect(harness.compiler.compiled.isEmpty)
        #expect(harness.logs.get().contains { $0.contains("not the files of the catalog") })

        // Downloading puts the checked file in its place.
        harness.publish(id, at: StoreSamples.privateStore)
        store.download([id])
        await store.waitUntilIdle()
        #expect(store.state(of: id) == .installed)
        #expect(store.uncheckedCopies.isEmpty)
        #expect(Set(harness.transport.requests.map(\.url)) == [harness.address(of: path, in: id)])
    }

    // MARK: Deleting

    @Test func deletingAModelUnloadsItFirstAndFreesItsSpace() async throws {
        let harness = StoreHarness()
        harness.publishDefaultSet()
        let store = harness.store
        await store.refresh()
        store.downloadRequiredModels()
        await store.waitUntilIdle()
        let unloaded = Shared<[[ModelArtifactID]]>([])
        store.unloadBeforeDeleting = { ids in
            // The files are still there when whoever has them loaded is told.
            #expect(harness.exists("installed.json", in: .cpt2))
            unloaded.update { $0.append(ids) }
        }
        let before = store.installedBytes

        await store.delete([.cpt2])

        #expect(unloaded.get() == [[.cpt2]])
        #expect(store.state(of: .cpt2) == .missing)
        #expect(store.installedFiles(of: .cpt2) == nil)
        #expect(harness.files(in: .cpt2).isEmpty)
        #expect(store.installedBytes == before - (4096 + 1500 + 700 + 400 + 120))
        #expect(store.state(of: .k2xl) == .installed)
        #expect(store.requiredModelsState == .missing(bytes: StoreSamples.artifact(.cpt2).downloadSize))
    }

    @Test func deletingEverythingAlsoEndsADownload() async throws {
        let harness = StoreHarness()
        harness.publishDefaultSet()
        harness.publish(.galTransl4B, at: StoreSamples.privateStore)
        harness.transport.hang(harness.address(of: "model.gguf", in: .galTransl4B), from: 2 * 1024)
        let store = harness.store
        await store.refresh()
        store.download(defaultSet + [.galTransl4B])
        await waitUntil("the default set is installed") { defaultSet.allSatisfy { store.state(of: $0) == .installed } }

        await store.deleteAll()
        await store.waitUntilIdle()

        #expect(StoreSamples.catalog.artifacts.allSatisfy { store.state(of: $0.id) == .missing })
        #expect(store.installedBytes == 0)
        let left = try FileManager.default.contentsOfDirectory(atPath: harness.root.path(percentEncoded: false))
        #expect(left.isEmpty)
    }

    // MARK: The network and the token

    @Test func aDownloadWithoutANetworkWaitsAndSaysSo() async throws {
        let harness = StoreHarness()
        harness.publishDefaultSet()
        harness.transport.hang(harness.address(of: "K2XL.mlpackage/Manifest.json", in: .k2xl))
        let store = harness.store
        await store.refresh()
        #expect(store.isConnected)

        harness.connectivity.yield(false)
        await waitUntil("the store knows there is no network") { !store.isConnected }
        store.downloadRequiredModels()
        if case .waitingForConnection = store.requiredModelsState {} else { Issue.record("\(store.requiredModelsState)") }

        harness.connectivity.yield(true)
        await waitUntil("the store knows the network is back") { store.isConnected }
        if case .downloading = store.requiredModelsState {} else { Issue.record("\(store.requiredModelsState)") }
        store.cancelDownloads()
        await store.waitUntilIdle()
    }

    @Test func theTokenIsKeptAndOnlyItsPresenceIsShown() async throws {
        let harness = StoreHarness(privateStore: false)
        let store = harness.store
        await store.refresh()
        #expect(!store.hasSourceToken)

        try await store.setSourceToken("another-made-up-token")
        #expect(store.hasSourceToken)
        #expect(harness.tokens.read() == "another-made-up-token")

        try await store.setSourceToken("")
        #expect(!store.hasSourceToken)
        #expect(harness.tokens.read() == nil)
    }

    // MARK: Woken in the background

    @Test func aWakeUpForAnotherSessionIsHandedBackAtOnce() async {
        let harness = StoreHarness()
        let completed = Shared(0)

        harness.store.handleBackgroundSessionEvents(identifier: "someone.else") { completed.update { $0 += 1 } }

        #expect(completed.get() == 1)
    }

    /// What arrived while the app was gone is installed; first loads wait for the foreground.
    @Test func aWakeUpInstallsWhatArrivedAndLeavesTheFirstLoad() async throws {
        let harness = StoreHarness()
        harness.transport.own(session: "the.session")
        // Everything arrived while the app was gone: the files are whole, in place.
        try harness.copyIn(.v4s)
        let store = harness.store
        let completed = Shared(0)

        store.handleBackgroundSessionEvents(identifier: "the.session") { completed.update { $0 += 1 } }
        await waitUntil("the model is installed") { store.state(of: .v4s) == .installed }
        #expect(completed.get() == 0)
        harness.transport.deliverEvents()
        await waitUntil("the system is told") { completed.get() == 1 }

        #expect(harness.compiler.compiled == ["V4S.mlpackage"])
        #expect(harness.compiler.prepared.isEmpty)
        #expect(store.installedFiles(of: .v4s)?.isPrepared == false)

        // A screen that shows the models asks again: now the model is loaded once.
        await store.refresh()
        await store.waitUntilIdle()
        #expect(harness.compiler.prepared == ["V4S.mlmodelc"])
        #expect(store.installedFiles(of: .v4s)?.isPrepared == true)
        #expect(completed.get() == 1)
    }
}
