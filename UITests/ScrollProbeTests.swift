import ObjectiveC
import XCTest

/// Flicks whatever list the already running app shows, for `Scripts/measure_touch.sh`: the
/// touches go through the system as a finger's do, so a recording of the list scrolled this
/// way can be set beside the list harness's scripted scroll.
///
/// The app is launched by the recording (`xctrace --launch`), not by this test, which waits
/// for it. `PROBE_FLICKS` is how many flicks, `PROBE_VELOCITY` their speed in points a second.
/// The list closes by itself; flicks after that find no app and end the test, which is not a
/// failure of the measurement.
///
/// XCUITest lets the app come to rest before and after every event, so a list flicked this
/// way stops between two flicks and its speed over the whole scroll stays far under a hand's.
/// With `PROBE_PACE=run` the test does not wait: the next flick lands on the moving list, as
/// a hand's does, and the speed reached depends on the flicks' speed and on `PROBE_PAUSE_MS`
/// between them. What speed that is, the harness measures; nothing here promises one.
final class ScrollProbeTests: XCTestCase {
    @MainActor
    func testFlicks() throws {
        let app = XCUIApplication()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 240), "the app is not running in front")
        let environment = ProcessInfo.processInfo.environment
        let flicks = Int(environment["PROBE_FLICKS"] ?? "") ?? 12
        let velocity = Double(environment["PROBE_VELOCITY"] ?? "") ?? 3_000
        let pause = UInt32(environment["PROBE_PAUSE_MS"] ?? "") ?? 0
        // The list's first screen settles.
        sleep(2)
        if environment["PROBE_PACE"] == "run" {
            XCTAssertTrue(Quiescence.skip(), "this XCTest has no wait for the app's rest to leave out")
        }
        for _ in 0..<flicks {
            guard app.state == .runningForeground else { break }
            app.swipeUp(velocity: XCUIGestureVelocity(rawValue: velocity))
            if pause > 0 { usleep(pause * 1_000) }
        }
    }
}

/// XCUITest's wait for the app to come to rest around every event, left out for the rest of
/// the test process. The wait is the test framework's own (`XCUIApplicationProcess`), found
/// by name: a framework that names it otherwise leaves `skip()` false and the test says so.
private enum Quiescence {
    static func skip() -> Bool {
        guard let process: AnyClass = NSClassFromString("XCUIApplicationProcess") else { return false }
        var count: UInt32 = 0
        guard let methods = class_copyMethodList(process, &count) else { return false }
        defer { free(methods) }
        var replaced = false
        for index in 0..<Int(count) {
            let method = methods[index]
            guard NSStringFromSelector(method_getName(method)).hasPrefix("waitForQuiescenceIncludingAnimationsIdle") else {
                continue
            }
            // The arguments after the receiver and the selector: one flag, or two.
            switch method_getNumberOfArguments(method) - 2 {
            case 1:
                let idle: @convention(block) (AnyObject, Bool) -> Void = { _, _ in }
                method_setImplementation(method, imp_implementationWithBlock(idle))
                replaced = true
            case 2:
                let idle: @convention(block) (AnyObject, Bool, Bool) -> Void = { _, _, _ in }
                method_setImplementation(method, imp_implementationWithBlock(idle))
                replaced = true
            default:
                continue
            }
        }
        return replaced
    }
}
