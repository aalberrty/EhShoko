import EhFeatures
import SwiftUI

/// What the sheet shows of the pages' states: whether any have failed (the Retry button at
/// rest) and whether the page on screen has its image (Save, Copy and Share need one).
///
/// The model keeps page states out of observation, so that a page that resolves touches that
/// page's view and nothing in SwiftUI. The sheet therefore looks, while it shows: at once,
/// and then at growing intervals after each page turn and each reload, which is when a page
/// arrives or fails. Eight looks over half a minute, then none until the reader moves again.
@Observable
final class LedgerPageWatch {
    private(set) var failedPageCount = 0
    private(set) var pageHasImage = false
    /// Raised to start looking again, after something the sheet did changed a page.
    private(set) var generation = 0

    func lookAgain() {
        generation += 1
    }

    /// Looks until the growing interval passes `longestPause`, or the task is cancelled.
    func follow(_ model: ReaderModel) async {
        var pause = Self.firstPause
        while !Task.isCancelled {
            look(at: model)
            guard pause <= Self.longestPause else { return }
            try? await Task.sleep(for: pause)
            pause = pause * 2
        }
    }

    private static let firstPause: Duration = .milliseconds(250)
    private static let longestPause: Duration = .seconds(16)

    private func look(at model: ReaderModel) {
        let failed = model.failedPageCount
        if failed != failedPageCount {
            failedPageCount = failed
        }
        // On the closing page the page on screen is still the last page.
        let hasImage = model.imageActions(for: model.currentPage).contains(.copy)
        if hasImage != pageHasImage {
            pageHasImage = hasImage
        }
    }
}

/// Runs the watch while the sheet shows, starting again when the reader moves. A view of its
/// own, behind the sheet's rows, so a page turn re-renders nothing else for it.
struct LedgerPageWatcher: View {
    let model: ReaderModel
    let watch: LedgerPageWatch

    private struct Trigger: Hashable {
        let page: Int
        let generation: Int
    }

    var body: some View {
        Color.clear
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .task(id: Trigger(page: model.currentPage, generation: watch.generation)) {
                await watch.follow(model)
            }
    }
}
