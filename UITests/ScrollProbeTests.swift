import XCTest

/// Flicks whatever list the already running app shows, for `Scripts/measure_touch.sh`: the
/// touches go through the system as a finger's do, so a recording of the list scrolled this
/// way can be set beside the list harness's scripted scroll.
///
/// The app is launched by the recording (`xctrace --launch`), not by this test, which waits
/// for it. `PROBE_FLICKS` is how many flicks, `PROBE_VELOCITY` their speed in points a second.
/// The list closes by itself; flicks after that find no app and end the test, which is not a
/// failure of the measurement.
final class ScrollProbeTests: XCTestCase {
    @MainActor
    func testFlicks() throws {
        let app = XCUIApplication()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 240), "the app is not running in front")
        let environment = ProcessInfo.processInfo.environment
        let flicks = Int(environment["PROBE_FLICKS"] ?? "") ?? 12
        let velocity = Double(environment["PROBE_VELOCITY"] ?? "") ?? 3_000
        // The list's first screen settles.
        sleep(2)
        for _ in 0..<flicks {
            guard app.state == .runningForeground else { break }
            app.swipeUp(velocity: XCUIGestureVelocity(rawValue: velocity))
        }
    }
}
