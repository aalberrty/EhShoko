import XCTest

/// Launches the app with `PROBE_ARGS` and attaches its accessibility tree, for writing walks.
final class ProbeTests: XCTestCase {
    @MainActor
    func testProbe() throws {
        let app = XCUIApplication()
        app.launchArguments = (ProcessInfo.processInfo.environment["PROBE_ARGS"] ?? "")
            .split(separator: " ").map(String.init)
        app.launch()
        _ = app.wait(for: .runningForeground, timeout: 30)
        sleep(8)
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = "tree"
        tree.lifetime = .keepAlways
        add(tree)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "screen"
        shot.lifetime = .keepAlways
        add(shot)
    }
}
