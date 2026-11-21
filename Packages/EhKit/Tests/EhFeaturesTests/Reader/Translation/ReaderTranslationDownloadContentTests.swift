import EhCore
import EhFeatures
import Testing

@Suite struct ReaderTranslationDownloadContentTests {
    private typealias Content = ReaderTranslationDownloadContent
    private let progress = ModelTransferProgress(completedBytes: 400, totalBytes: 1_000)

    @Test func readyToDownloadOffersTheDownloadBesideKeepReading() {
        let content = Content(state: .missing(bytes: 1_180), isConnected: true)
        #expect(content.fraction == nil)
        #expect(content.line == nil)
        #expect(content.detail == nil)
        #expect(content.secondary == .keepReading)
        #expect(content.primary == .download(bytes: 1_180))
        #expect(!content.isTransferring)
    }

    @Test func readyToDownloadWithoutANetworkSaysSo() {
        let content = Content(state: .missing(bytes: 1_180), isConnected: false)
        #expect(content.detail == .offline)
        #expect(content.primary == .download(bytes: 1_180))
    }

    @Test func downloadingShowsTheBytesAndOffersPause() {
        let content = Content(state: .downloading(progress), isConnected: true)
        #expect(content.fraction == 0.4)
        #expect(content.line == .progress(progress))
        #expect(content.detail == nil)
        #expect(content.secondary == .pause)
        #expect(content.primary == .keepReading)
        #expect(content.isTransferring)
    }

    @Test func waitingForAConnectionKeepsTheBarAndDoesNotEstimate() {
        let content = Content(state: .waitingForConnection(progress), isConnected: false)
        #expect(content.fraction == 0.4)
        #expect(content.line == .progress(progress))
        #expect(content.detail == .offline)
        #expect(content.secondary == .pause)
        #expect(content.primary == .keepReading)
        #expect(!content.isTransferring)
    }

    @Test func pausedOffersResume() {
        let content = Content(state: .paused(progress), isConnected: true)
        #expect(content.fraction == 0.4)
        #expect(content.line == .paused(progress))
        #expect(content.secondary == .keepReading)
        #expect(content.primary == .resume)
        #expect(!content.isTransferring)
    }

    @Test func preparingHasAFullBarAndOneButton() {
        let content = Content(state: .preparing, isConnected: true)
        #expect(content.fraction == 1)
        #expect(content.line == nil)
        #expect(content.detail == .preparing)
        #expect(content.secondary == nil)
        #expect(content.primary == .keepReading)
    }

    @Test func readySaysSoWithOneButton() {
        let content = Content(state: .ready, isConnected: true)
        #expect(content.fraction == nil)
        #expect(content.line == .ready)
        #expect(content.secondary == nil)
        #expect(content.primary == .keepReading)
    }

    @Test(arguments: [ModelSetState.unavailable, .failed(.noSource)])
    func noSourceOffersOpenSettings(state: ModelSetState) {
        let content = Content(state: state, isConnected: true)
        #expect(content.line == nil)
        #expect(content.detail == .noSource)
        #expect(content.secondary == .keepReading)
        #expect(content.primary == .openSettings)
    }

    @Test func noSpaceOffersOpenSettingsBesideTryAgain() {
        let content = Content(state: .failed(.noSpace(needed: 300, available: 150)), isConnected: true)
        #expect(content.line == .stopped)
        #expect(content.detail == .noSpace(needed: 300, available: 150))
        #expect(content.secondary == .openSettings)
        #expect(content.primary == .retry)
    }

    @Test func noSpaceInTheMiddleOfADownloadGivesNoFigures() {
        let content = Content(state: .failed(.noSpace(needed: 0, available: 0)), isConnected: true)
        #expect(content.line == .stopped)
        #expect(content.detail == nil)
        #expect(content.secondary == .openSettings)
        #expect(content.primary == .retry)
    }

    @Test func aChecksumFailureSaysSoAndOffersTryAgain() {
        let content = Content(state: .failed(.checksumMismatch), isConnected: true)
        #expect(content.line == .stopped)
        #expect(content.detail == .checksumMismatch)
        #expect(content.secondary == .keepReading)
        #expect(content.primary == .retry)
    }

    @Test(arguments: [ModelStoreFailure.refused(status: 404), .unreachable, .installFailed])
    func otherFailuresOfferTryAgain(failure: ModelStoreFailure) {
        let content = Content(state: .failed(failure), isConnected: true)
        #expect(content.line == .stopped)
        #expect(content.detail == nil)
        #expect(content.secondary == .keepReading)
        #expect(content.primary == .retry)
    }
}
