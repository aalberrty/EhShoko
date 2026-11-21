import EhCore
@testable import EhFeatures
import Foundation
import Synchronization
import Testing

@Suite struct ReaderTranslationDownloadModelTests {
    @Test func creatingTheModelReadsNothing() {
        let harness = TranslationStoreHarness()
        _ = ReaderTranslationDownloadModel(store: harness.store)
        #expect(!harness.store.isLoaded)
        #expect(harness.transport.requests.isEmpty)
    }

    @Test func withoutASourceItOffersOpenSettings() async {
        let harness = TranslationStoreHarness(privateStore: false)
        let model = ReaderTranslationDownloadModel(store: harness.store)
        await model.load()
        #expect(model.content.detail == .noSource)
        #expect(model.content.primary == .openSettings)
        #expect(!model.isReady)
    }

    @Test func theDownloadButtonStartsTheDownloadAndPauseStopsIt() async {
        let harness = TranslationStoreHarness()
        harness.hold(.k2xl)
        let model = ReaderTranslationDownloadModel(store: harness.store)
        await model.load()
        guard case .download = model.content.primary else {
            Issue.record("Nothing installed offers the download, not \(model.content.primary)")
            return
        }

        model.perform(model.content.primary)
        await waitFor("the detector is being fetched") { harness.isWaiting(.k2xl) }
        #expect(model.content.secondary == .pause)

        model.perform(.pause)
        await waitFor("the download is paused") {
            if case .paused = harness.store.requiredModelsState { true } else { false }
        }
        #expect(model.content.primary == .resume)
        harness.release(.k2xl)
    }

    @Test func theSheetsOwnActionsLeaveTheStoreAlone() async {
        let harness = TranslationStoreHarness()
        let model = ReaderTranslationDownloadModel(store: harness.store)
        await model.load()
        let before = harness.store.requiredModelsState
        model.perform(.keepReading)
        model.perform(.openSettings)
        #expect(harness.store.requiredModelsState == before)
        #expect(harness.transport.requests.isEmpty)
    }

    @Test func isReadyOnceTheModelsAreInstalled() async throws {
        let harness = TranslationStoreHarness()
        try await harness.installDefaultSet()
        let model = ReaderTranslationDownloadModel(store: harness.store)
        #expect(model.isReady)
        #expect(model.content.line == .ready)
    }

    @Test func theTimeLeftFollowsTheDownloadAndGoesWhenItStops() {
        let harness = TranslationStoreHarness()
        let model = ReaderTranslationDownloadModel(store: harness.store)
        let start = ContinuousClock.now
        let megabyte: Int64 = 1_000_000
        func downloading(_ megabytes: Int64) -> ModelSetState {
            .downloading(ModelTransferProgress(completedBytes: megabytes * megabyte, totalBytes: 1_200 * megabyte))
        }

        model.note(downloading(0), at: start)
        model.note(downloading(3), at: start + .seconds(3))
        #expect(model.timeLeft == nil)
        model.note(downloading(10), at: start + .seconds(10))
        // 1 MB/s with 1,190 MB left: 19.8 minutes, rounded up.
        #expect(model.timeLeft == .seconds(20 * 60))

        let paused = ModelTransferProgress(completedBytes: 10 * megabyte, totalBytes: 1_200 * megabyte)
        model.note(.paused(paused), at: start + .seconds(11))
        #expect(model.timeLeft == nil)
        model.note(.waitingForConnection(paused), at: start + .seconds(12))
        #expect(model.timeLeft == nil)
    }

    @Test func theTimeLeftIsSetOnlyWhenItChanges() {
        let harness = TranslationStoreHarness()
        let model = ReaderTranslationDownloadModel(store: harness.store)
        let start = ContinuousClock.now
        let megabyte: Int64 = 1_000_000
        func downloading(_ megabytes: Int64) -> ModelSetState {
            .downloading(ModelTransferProgress(completedBytes: megabytes * megabyte, totalBytes: 1_200 * megabyte))
        }
        model.note(downloading(0), at: start)
        model.note(downloading(10), at: start + .seconds(10))
        #expect(model.timeLeft == .seconds(20 * 60))

        let changes = ChangeCounter()
        withObservationTracking { _ = model.timeLeft } onChange: { changes.count.withLock { $0 += 1 } }
        // Still 20 minutes: nothing an observer would see.
        model.note(downloading(11), at: start + .seconds(11))
        #expect(changes.count.withLock { $0 } == 0)
        model.note(downloading(100), at: start + .seconds(20))
        #expect(changes.count.withLock { $0 } == 1)
    }
}

nonisolated private final class ChangeCounter: Sendable {
    let count = Mutex(0)
}
