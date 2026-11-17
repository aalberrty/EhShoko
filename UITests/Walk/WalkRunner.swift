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
    /// Runtime warnings the app raised during the step, noted in the record.
    var takeWarnings: () -> [String] = { [] }
    var attach: (XCTAttachment) -> Void = { _ in }

    private(set) var record: WalkRecord
    private var path: [String] = []
    private var screenshots = 0
    private var trees = 0
    private var audits = 0
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

    /// The screen's accessibility audit, attached as `<walk>__audit-<nn>-<name>` with one line
    /// per issue, and counted in the walk's notes. Every issue is handed back as handled, so the
    /// audit reports and does not fail the walk.
    func audit(named name: String) {
        audits += 1
        var lines: [String] = []
        do {
            try app.performAccessibilityAudit { issue in
                lines.append(Self.line(for: issue))
                return true
            }
        } catch {
            lines.append("The audit could not run: \(error.localizedDescription)")
        }
        let attachment = XCTAttachment(string: lines.isEmpty ? "No issues." : lines.joined(separator: "\n"))
        attachment.name = String(format: "%@__audit-%02d-%@", walk.id, audits, name)
        attachment.lifetime = .keepAlways
        attach(attachment)
        record.notes.append("audit \(name): \(lines.count) issue\(lines.count == 1 ? "" : "s")")
    }

    /// "Contrast · Contrast nearly passed · “Couldn't load Popular” (type 48) at 20,398, 180×18";
    /// the type is `XCUIElement.ElementType`'s raw value (48 static text, 9 button, 1 other).
    private static func line(for issue: XCUIAccessibilityAuditIssue) -> String {
        let types: [(XCUIAccessibilityAuditType, String)] = [
            (.contrast, "Contrast"), (.elementDetection, "Element detection"), (.hitRegion, "Hit region"),
            (.sufficientElementDescription, "Description"), (.dynamicType, "Dynamic Type"),
            (.textClipped, "Text clipped"), (.trait, "Trait"),
        ]
        let type = types.first { issue.auditType.contains($0.0) }?.1 ?? "Type \(issue.auditType.rawValue)"
        var element = "no element"
        if let found = issue.element, found.exists {
            let label = found.label.isEmpty ? (found.identifier.isEmpty ? "unlabelled" : found.identifier) : found.label
            let frame = found.frame
            element = "“\(label)” (type \(found.elementType.rawValue)) at \(Int(frame.minX)),\(Int(frame.minY)),"
                + " \(Int(frame.width))×\(Int(frame.height))"
        }
        return "\(type) · \(issue.compactDescription) · \(element)"
    }

    // MARK: Steps

    private func perform(_ step: Step) throws {
        path.append(step.name)
        defer { path.removeLast() }
        try XCTContext.runActivity(named: currentStep) { _ in
            try act(step)
            for warning in takeWarnings() {
                record.notes.append("\(currentStep): runtime warning: \(warning.prefix(300))")
            }
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
            _ = try find(target)
            try tap(target)
        case .tapIfPresent(let target, let within):
            if target.element(in: app).waitForExistence(timeout: within) {
                try tap(target)
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
                try tap(target)
                element.typeText(text)
            } else {
                app.typeText(text)
            }
        case .scrollColumn(let direction, let screens):
            try scrollInLastColumn(direction, screens: screens)
        case .scrollTo(let target, let screens):
            try scrollTo(target, screens: screens)
        case .swipeUntil(let target, let direction, let times):
            try swipe(direction, until: target, times: times)
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
        case .backSwipe(let reach):
            try backSwipe(reach: reach)
        case .pause(let seconds):
            Thread.sleep(forTimeInterval: seconds)
        case .screenshot(let name):
            screenshot(named: name)
            if environment.dumpsTrees { dumpTree(named: name) }
        case .dump(let name):
            dumpTree(named: name)
        case .audit(let name):
            audit(named: name)
        case .ifPresent(let target, let within, let then, let otherwise):
            let present = target.element(in: app).waitForExistence(timeout: within)
            for step in present ? then : otherwise { try perform(step) }
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

    /// Taps the first element of the target that has a frame on screen.
    ///
    /// Elements with an empty frame are skipped before XCTest sees them: when it cannot work
    /// out an element's hittability (a menu item's twin with no frame) it ends the test on the
    /// spot, which `continueAfterFailure` does not prevent. The tap itself is XCTest's, which
    /// finds the element's hit point and scrolls it into view (a row clipped by an iPad's form
    /// sheet has an on-screen frame but must not be tapped at its middle).
    private func tap(_ target: Target) throws {
        // A short settle: a control that has just appeared may still be moving.
        Thread.sleep(forTimeInterval: 0.3)
        let window = app.frame
        var candidates = target.query(in: app).allElementsBoundByIndex.filter { element in
            let frame = element.frame
            return frame.width >= 1 && frame.height >= 1
        }
        if target.picksLast { candidates.reverse() }
        guard let element = candidates.first(where: { window.intersects($0.frame) }) ?? candidates.first else {
            throw WalkFailure(step: currentStep, reason: "\(target) has no element with a frame")
        }
        element.tap()
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

    private func swipe(_ direction: Step.Direction, until target: Target, times: Int) throws {
        let element = target.element(in: app)
        for _ in 0...times {
            // On screen, not only in the tree: a strip keeps the next page's views below the fold.
            if element.waitForExistence(timeout: 1.5), app.frame.contains(CGPoint(x: element.frame.midX, y: element.frame.midY)) {
                return
            }
            switch direction {
            case .up: app.swipeUp()
            case .down: app.swipeDown()
            case .left: app.swipeLeft()
            case .right: app.swipeRight()
            }
        }
        throw WalkFailure(step: currentStep, reason: "\(target) did not appear after \(times) swipes \(direction.rawValue)")
    }

    /// The system back button (`BackButton` on iOS 26; on iOS 18 a SwiftUI stack's has no
    /// identifier, only the previous screen's title, so the leading button of a navigation
    /// bar), or the edge swipe where a page draws its own top bar.
    /// The navigation bar of the screen pushed last: the trailing-most one (an iPad's side pane,
    /// or a form sheet over the screen), or `nil` when no bar shows.
    private var lastColumnBar: CGRect? {
        app.navigationBars.allElementsBoundByIndex.map(\.frame)
            .filter { !$0.isEmpty && app.frame.intersects($0) }
            .max { $0.minX < $1.minX }
    }

    /// Where the column of the screen pushed last starts (0 when one screen fills the window).
    private var lastColumnMinX: CGFloat { lastColumnBar?.minX ?? 0 }

    /// Drags under the last column's bar, from half to a tenth of the room below it: inside a
    /// side pane or an iPad's form sheet, whose bottom is above the window's.
    private func scrollInLastColumn(_ direction: Step.Direction, screens: Double) throws {
        guard direction == .up || direction == .down else {
            throw WalkFailure(step: currentStep, reason: "a column scrolls only up or down")
        }
        let window = app.frame
        let bar = lastColumnBar ?? CGRect(x: window.minX, y: window.minY, width: window.width, height: 0)
        let top = bar.maxY, room = window.maxY - bar.maxY
        let (from, to): (CGFloat, CGFloat) = direction == .down ? (0.5, 0.1) : (0.1, 0.5)
        let origin = app.coordinate(withNormalizedOffset: .zero)
        for _ in 0..<max(Int((screens * window.height / (room * 0.4)).rounded(.up)), 1) {
            let start = origin.withOffset(CGVector(dx: bar.midX, dy: top + room * from))
            let end = origin.withOffset(CGVector(dx: bar.midX, dy: top + room * to))
            start.press(forDuration: 0.05, thenDragTo: end, withVelocity: 900, thenHoldForDuration: 0.15)
        }
    }

    private func backSwipe(reach: Double) throws {
        let width = app.frame.width
        // The column of the screen pushed last.
        let leadingEdge = lastColumnMinX
        // A drag from a column's edge (the side pane's) does not reach its back gesture on
        // every system: there the walk goes back with the button, and says so.
        if leadingEdge > 1 {
            record.notes.append("\(currentStep): the screen is in a column at \(Int(leadingEdge)) pt; "
                + (reach < 0.5 ? "no swipe" : "went back with the button"))
            if reach >= 0.5 { try goBack() }
            return
        }
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 2 / width, dy: 0.5))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: reach, dy: 0.5))
        // Slowly, and held before letting go, so the finger has no speed left that would finish
        // the pop by itself.
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: 80, thenHoldForDuration: 0.6)
        Thread.sleep(forTimeInterval: 1.2)
    }

    private func goBack() throws {
        let bars = app.navigationBars.allElementsBoundByIndex.filter { !$0.frame.isEmpty }
        let identified = app.navigationBars.buttons.matching(identifier: "BackButton").allElementsBoundByIndex
            .filter { !$0.frame.isEmpty && app.frame.intersects($0.frame) }
        let leading = bars.compactMap { bar -> XCUIElement? in
            bar.buttons.allElementsBoundByIndex.first { $0.frame.minX - bar.frame.minX < 24 && !$0.frame.isEmpty }
        }
        // On an iPad several columns have a bar: the screen pushed last is in the trailing one
        // (the side pane's). A pane's Close is not a way back.
        let closes = ["Close", "xmark"]
        let button = (identified + leading)
            .filter { !closes.contains($0.label) && !closes.contains($0.identifier) }
            .max { $0.frame.minX < $1.frame.minX }
        if let button {
            let frame = button.frame
            app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: frame.midX, dy: frame.midY)).tap()
        } else {
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
