import EhCore
@testable import EhFeatures
import Foundation
import Testing

/// `ReaderTranslationPageStatuses`: which page the controls' status speaks for, and the failed
/// pages on screen.
@Suite struct ReaderTranslationPageStatusesTests {
    private typealias Statuses = ReaderTranslationPageStatuses

    private func statuses(_ pages: [Int: PageTranslationStatus]) -> Statuses {
        var statuses = Statuses()
        for (page, status) in pages { statuses.record(status, of: page) }
        return statuses
    }

    @Test(arguments: [
        (PageTranslationStatus.loadingModels, ReaderTranslationStatus.gettingReady),
        (.translating, .translating(page: 4)),
        (.failed(.pipelineFailed), .failed(page: 4)),
    ])
    func theCurrentPageSpeaksWhileItHasSomethingToSay(_ own: PageTranslationStatus, _ expected: ReaderTranslationStatus) {
        let summary = statuses([4: own, 5: .failed(.pipelineFailed)]).summary(current: 4, onScreen: [4, 5])
        #expect(summary.status == expected)
    }

    @Test(arguments: [PageTranslationStatus.nothingToDraw, .skipped, .translated(PageTranslationOverlay(
        patchFile: URL(fileURLWithPath: "/patches/4"), variant: "v1"
    ))])
    func theOtherPagesFailureTakesTheLineWhenTheCurrentPageIsDone(_ own: PageTranslationStatus) {
        let summary = statuses([4: own, 5: .failed(.pipelineFailed)]).summary(current: 4, onScreen: [4, 5])
        #expect(summary.status == .failed(page: 5))
        #expect(summary.failedOnScreen == [5])
    }

    @Test func aCurrentPageThatHasSaidNothingGivesTheLineToo() {
        let summary = statuses([5: .failed(.pipelineFailed)]).summary(current: 4, onScreen: [4, 5])
        #expect(summary.status == .failed(page: 5))
    }

    @Test func theFailedPagesAreNearestFirst() {
        let all = statuses([3: .failed(.pipelineFailed), 4: .nothingToDraw, 5: .failed(.pipelineFailed)])
        let summary = all.summary(current: 4, onScreen: [4, 5, 3])
        #expect(summary.failedOnScreen == [5, 3])
        #expect(summary.status == .failed(page: 5))
    }

    @Test func midTurnOnlyTheCurrentPageCounts() {
        let summary = statuses([6: .failed(.pipelineFailed)]).summary(current: 4, onScreen: [6, 7])
        #expect(summary.status == nil)
        #expect(summary.failedOnScreen.isEmpty)
    }

    @Test func askingAgainAndClearingEndTheFailure() {
        var all = statuses([5: .failed(.pipelineFailed)])
        all.askAgain(5)
        #expect(all.status(of: 5) == .translating(page: 5))
        all.record(.failed(.pipelineFailed), of: 5)
        all.clear()
        #expect(all.summary(current: 4, onScreen: [4, 5]).failedOnScreen.isEmpty)
    }

    @Test func anOverlayIsDrawnAgainOnceThenThePageFails() {
        var all = statuses([5: .translated(PageTranslationOverlay(patchFile: URL(fileURLWithPath: "/p/5"), variant: "v1"))])
        #expect(all.overlayDidFail(page: 5))
        #expect(!all.hasFailed(5))
        #expect(!all.overlayDidFail(page: 5))
        #expect(all.hasFailed(5))
        // The service's word ends the reader's own failure.
        all.record(.translating, of: 5)
        #expect(!all.hasFailed(5))
    }
}
