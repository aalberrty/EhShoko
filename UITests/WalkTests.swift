import ObjectiveC
import Synchronization
import XCTest

/// Runs the walks the environment asks for (`WALKS`, see `WalkEnvironment`), each as a test of
/// its own named `test_<walk id>` (dashes become underscores), so a result bundle has one
/// result, one duration and one set of screenshots per walk, and a walk that fails does not
/// stop the next.
///
/// The tests are added when XCTest asks for the suite, so they do not show in Xcode's test
/// navigator; `Scripts/run_walks.sh` runs them.
@MainActor
final class WalkTests: XCTestCase {
    /// XCTest's own failures during the walk; `record(_:)`, which XCTest calls without the
    /// main actor, writes them.
    private let issues = Mutex(Issues())

    private struct Issues {
        var isWalking = false
        /// A failure XCTest recorded during the current step, which fails the walk at the
        /// step's end.
        var pending: String?
        /// Whether XCTest recorded a failure, so the walk's failure is not recorded twice.
        var recordedAny = false
    }

    nonisolated override class var defaultTestSuite: XCTestSuite {
        MainActor.assumeIsolated {
            for walk in WalkCatalogue.selected(by: WalkEnvironment.current) {
                addTest(running: walk.id)
            }
        }
        return super.defaultTestSuite
    }

    /// Adds `test_<id>` to the class, whose body runs that walk.
    private static func addTest(running id: String) {
        let selector = NSSelectorFromString(testName(of: id))
        guard !instancesRespond(to: selector) else { return }
        let body: @convention(block) (WalkTests) -> Void = { test in
            MainActor.assumeIsolated { test.runWalk(id: id) }
        }
        class_addMethod(self, selector, imp_implementationWithBlock(body), "v@:")
    }

    static func testName(of walk: String) -> String {
        "test_" + walk.replacingOccurrences(of: "-", with: "_")
    }

    private func runWalk(id: String) {
        // A failure inside XCTest (a lost app, a query that cannot be answered) must not end
        // the test before its screenshot and its record are attached.
        continueAfterFailure = true
        let environment = WalkEnvironment.current
        guard let walk = WalkCatalogue.walk(id: id, in: environment) else {
            XCTFail("No walk \(id)")
            return
        }
        let runner = WalkRunner(app: XCUIApplication(), walk: walk, environment: environment)
        runner.attach = { [unowned self] attachment in add(attachment) }
        runner.takeIssue = { [unowned self] in
            issues.withLock { state in
                defer { state.pending = nil }
                return state.pending
            }
        }
        issues.withLock { $0.isWalking = true }
        do {
            try runner.run()
            add(runner.record.attachment)
        } catch {
            runner.screenshot(named: "FAILED")
            if runner.app.state == .runningForeground { runner.dumpTree(named: "FAILED") }
            add(runner.record.attachment)
            let failure = error as? WalkFailure ?? WalkFailure(step: runner.currentStep, reason: "\(error)")
            let recordedAlready = issues.withLock { state in
                state.isWalking = false
                return state.recordedAny
            }
            if !recordedAlready {
                record(XCTIssue(type: .assertionFailure, compactDescription: "\(failure.step): \(failure.reason)"))
            }
        }
    }

    /// XCTest's own failures during a walk (for example a tap on an element that went away)
    /// are kept for the step to report, which ends the walk there.
    nonisolated override func record(_ issue: XCTIssue) {
        let description = issue.compactDescription
        issues.withLock { state in
            guard state.isWalking else { return }
            state.recordedAny = true
            if state.pending == nil { state.pending = description }
        }
        super.record(issue)
    }
}
