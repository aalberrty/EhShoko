import XCTest

/// Why a step could not be done.
struct WalkFailure: Error, Sendable {
    var step: String
    var reason: String
}

/// Performs a walk's steps on the app, one XCTest activity per step, and keeps what happened
/// for the results (`WalkRecord`).
@MainActor
final class WalkRunner {
    let app: XCUIApplication
    let walk: Walk
    let environment: WalkEnvironment
    /// Called after every step; a failure XCTest recorded during the step (a query that
    /// failed, the app that crashed) comes back here and fails the walk.
    var takeIssue: () -> String? = { nil }
    var attach: (XCTAttachment) -> Void = { _ in }

    private(set) var record: WalkRecord
    private var path: [String] = []
    private var screenshots = 0
    private var trees = 0
    private var hasLaunched = false

    init(app: XCUIApplication, walk: Walk, environment: WalkEnvironment) {
        self.app = app
        self.walk = walk
        self.environment = environment
        record = WalkRecord(walk: walk)
    }

    var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    /// The name of the step running now, with the groups it is in.
    var currentStep: String { path.joined(separator: " › ") }

    func run() throws {
        let start = Date()
        defer { record.seconds = Date().timeIntervalSince(start) }
        var firstFailure: WalkFailure?
        for step in walk.steps {
            let stepStart = Date()
            do {
                try perform(step)
                record.steps.append(.init(name: step.name, seconds: Date().timeIntervalSince(stepStart), passed: true))
            } catch let failure as WalkFailure {
                record.steps.append(.init(name: step.name, seconds: Date().timeIntervalSince(stepStart), passed: false))
                record.fail(failure)
                guard environment.keepsGoing else { throw failure }
                // Surveying a walk: note the failure, show where it happened, and go on.
                screenshot(named: "failed-\(record.steps.count)")
                dumpTree(named: "failed-\(record.steps.count)")
                record.notes.append("\(failure.step): \(failure.reason)")
                firstFailure = firstFailure ?? failure
            }
        }
        if let firstFailure { throw firstFailure }
        record.passed = true
    }

    /// A screenshot attached under the walk's name: `<walk>__<nn>-<name>`.
    func screenshot(named name: String) {
        screenshots += 1
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = String(format: "%@__%02d-%@", walk.id, screenshots, name)
        attachment.lifetime = .keepAlways
        attach(attachment)
        record.screenshots.append(attachment.name ?? name)
    }

    /// The accessibility tree as text, attached as `<walk>__tree-<name>`.
    func dumpTree(named name: String) {
        let attachment = XCTAttachment(string: app.debugDescription)
        trees += 1
        attachment.name = String(format: "%@__tree-%02d-%@", walk.id, trees, name)
        attachment.lifetime = .keepAlways
        attach(attachment)
    }

    // MARK: Steps

    private func perform(_ step: Step) throws {
        path.append(step.name)
        defer { path.removeLast() }
        try XCTContext.runActivity(named: currentStep) { _ in
            try act(step)
            if let issue = takeIssue() {
                throw WalkFailure(step: currentStep, reason: issue)
            }
        }
    }

    private func act(_ step: Step) throws {
        switch step {
        case .launch(let extra):
            launch(extra: extra)
        case .terminate:
            app.terminate()
        case .tap(let target):
            try tap(try find(target))
        case .tapIfPresent(let target, let within):
            let element = target.element(in: app)
            if element.waitForExistence(timeout: within) {
                try tap(element)
            }
        case .tapPoint(let x, let y):
            app.coordinate(withNormalizedOffset: CGVector(dx: x, dy: y)).tap()
        case .longPress(let target, let seconds):
            try find(target).press(forDuration: seconds)
        case .swipe(let direction, let target):
            let element = try target.map { try find($0) } ?? app
            switch direction {
            case .up: element.swipeUp()
            case .down: element.swipeDown()
            case .left: element.swipeLeft()
            case .right: element.swipeRight()
            }
        case .scroll(let direction, let screens, let target):
            try scroll(direction, screens: screens, on: target.map { try find($0) } ?? app)
        case .pinch(let scale, let target):
            let element = try target.map { try find($0) } ?? app
            element.pinch(withScale: scale, velocity: scale < 1 ? -1 : 1)
        case .type(let text, let target):
            if let target {
                let element = try find(target)
                try tap(element)
                element.typeText(text)
            } else {
                app.typeText(text)
            }
        case .scrollTo(let target, let screens):
            try scrollTo(target, screens: screens)
        case .wait(let target, let timeout):
            _ = try find(target, timeout: timeout)
        case .waitGone(let target, let timeout):
            let gone = NSPredicate(format: "exists == false")
            let expectation = XCTNSPredicateExpectation(predicate: gone, object: target.element(in: app))
            if XCTWaiter.wait(for: [expectation], timeout: scaled(timeout)) != .completed {
                throw WalkFailure(step: currentStep, reason: "\(target) was still there after \(Int(scaled(timeout))) s")
            }
        case .expect(let target):
            _ = try find(target, timeout: 10)
        case .rotate(let orientation):
            if isPad {
                XCUIDevice.shared.orientation = orientation
                // The rotation animates; what follows should see the new layout.
                Thread.sleep(forTimeInterval: 1.5)
            }
        case .back:
            try goBack()
        case .pause(let seconds):
            Thread.sleep(forTimeInterval: seconds)
        case .screenshot(let name):
            screenshot(named: name)
            if environment.dumpsTrees { dumpTree(named: name) }
        case .dump(let name):
            dumpTree(named: name)
        case .group(_, let steps):
            for step in steps { try perform(step) }
        case .optional(let steps):
            do {
                for step in steps { try perform(step) }
            } catch let failure as WalkFailure {
                record.notes.append("\(failure.step): \(failure.reason) (optional, the walk went on)")
            }
        case .onPad(let steps):
            if isPad { for step in steps { try perform(step) } }
        case .onPhone(let steps):
            if !isPad { for step in steps { try perform(step) } }
        }
    }

    private func launch(extra: [String]) {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = walk.launch + extra
        if environment.attachesToRunningApp, !hasLaunched {
            // Instruments launched it with the same arguments (`trace_walk.sh`).
            app.activate()
        } else {
            app.launch()
        }
        _ = app.wait(for: .runningForeground, timeout: scaled(30))
        if !hasLaunched, environment.holdAfterFirstLaunch > 0 {
            // Instruments attaches meanwhile (`trace_walk.sh`).
            Thread.sleep(forTimeInterval: environment.holdAfterFirstLaunch)
        }
        hasLaunched = true
    }

    // MARK: Elements

    /// Waits for the target and returns it, or fails the step. `timeout` is for an unloaded
    /// machine; `WALK_PATIENCE` scales it.
    private func find(_ target: Target, timeout: Double = Step.patience) throws -> XCUIElement {
        let element = target.element(in: app)
        let wait = scaled(timeout)
        guard element.waitForExistence(timeout: wait) else {
            if app.state != .runningForeground {
                throw WalkFailure(step: currentStep, reason: "the app is not running (state \(app.state.rawValue)) while looking for \(target)")
            }
            throw WalkFailure(step: currentStep, reason: "\(target) did not appear within \(Int(wait)) s")
        }
        return element
    }

    /// Taps the element, waiting briefly for it to become hittable; an element that exists
    /// but reports itself not hittable (under a glass bar, in a SwiftUI overlay) is tapped
    /// at its middle.
    private func tap(_ element: XCUIElement) throws {
        let hittable = NSPredicate(format: "hittable == true")
        let expectation = XCTNSPredicateExpectation(predicate: hittable, object: element)
        if XCTWaiter.wait(for: [expectation], timeout: 3) == .completed {
            element.tap()
        } else {
            element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
    }

    private func scroll(_ direction: Step.Direction, screens: Double, on element: XCUIElement) throws {
        // Each drag moves the content 0.6 of the element, from 0.8 to 0.2 of it, and holds
        // before letting go so that nothing flings.
        let drags = max(Int((screens / 0.6).rounded(.up)), 1)
        let (from, to): (CGVector, CGVector) = switch direction {
        case .down: (CGVector(dx: 0.5, dy: 0.8), CGVector(dx: 0.5, dy: 0.2))
        case .up: (CGVector(dx: 0.5, dy: 0.2), CGVector(dx: 0.5, dy: 0.8))
        case .right: (CGVector(dx: 0.8, dy: 0.5), CGVector(dx: 0.2, dy: 0.5))
        case .left: (CGVector(dx: 0.2, dy: 0.5), CGVector(dx: 0.8, dy: 0.5))
        }
        for _ in 0..<drags {
            let start = element.coordinate(withNormalizedOffset: from)
            let end = element.coordinate(withNormalizedOffset: to)
            start.press(forDuration: 0.05, thenDragTo: end, withVelocity: 900, thenHoldForDuration: 0.15)
        }
    }

    private func scrollTo(_ target: Target, screens: Int) throws {
        let element = target.element(in: app)
        for _ in 0...screens {
            if element.waitForExistence(timeout: 1.5), element.isHittable { return }
            // From the middle of the window, which is inside a form sheet on an iPad too.
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.62))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.38))
            start.press(forDuration: 0.05, thenDragTo: end, withVelocity: 900, thenHoldForDuration: 0.15)
        }
        throw WalkFailure(step: currentStep, reason: "\(target) was not found after scrolling \(screens) times")
    }

    private func goBack() throws {
        let button = app.navigationBars.buttons.matching(identifier: "BackButton").allElementsBoundByIndex
            .first { $0.isHittable }
        if let button {
            button.tap()
        } else {
            // No system back button (a custom top bar): the edge swipe.
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.005, dy: 0.5))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5))
            start.press(forDuration: 0.05, thenDragTo: end, withVelocity: 1200, thenHoldForDuration: 0.05)
        }
        Thread.sleep(forTimeInterval: 0.8)
    }

    /// Every wait is written for the default patience (20 s); `WALK_PATIENCE` stretches them all.
    private func scaled(_ seconds: Double) -> Double {
        seconds * environment.patience / Step.patience
    }
}
