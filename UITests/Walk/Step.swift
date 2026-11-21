import XCTest

/// One thing a walk does. Walks are lists of steps (`Walk`), written with the constructors
/// below; `WalkRunner` performs them. A step that cannot be done fails the walk with its
/// name, a screenshot and the reason, and the run goes on to the next walk.
indirect enum Step: Sendable {
    /// Starts the app afresh with these launch arguments, after the walk's own (`Walk.launch`).
    case launch(extra: [String])
    /// Ends the app.
    case terminate
    case tap(Target)
    /// Taps the target if it shows up within `within` seconds; otherwise does nothing.
    case tapIfPresent(Target, within: Double)
    /// A point of the app's window, in fractions of its width and height (0.5, 0.5 is the
    /// middle): the reader's zones, which have no element.
    case tapPoint(x: Double, y: Double)
    case longPress(Target, seconds: Double)
    /// A finger down on the target that moves by this many points and lifts (a handle dragged).
    case drag(Target, dx: Double, dy: Double)
    case swipe(Direction, on: Target?)
    /// Drags the content by `screens` window heights (or widths), slowly enough that it does
    /// not fling, so a scroll goes as far as asked.
    case scroll(Direction, screens: Double, on: Target?)
    /// Pinches the target, or the middle of the window: below 1 together, above 1 apart.
    case pinch(scale: Double, on: Target?)
    /// Types into the target, or into whatever has the keyboard focus.
    case type(String, into: Target?)
    /// Drags up or down by about `screens` window heights in the column of the screen pushed
    /// last: on an iPad the side pane's or a form sheet's (the window's middle is the list
    /// beside the pane, its lower part below the sheet), elsewhere the whole window.
    case scrollColumn(Direction, screens: Double)
    /// Scrolls down (up to `screens` times) until the target is on screen: rows of a lazy
    /// list exist only once they are near it.
    case scrollTo(Target, screens: Int)
    /// Swipes the window in a direction (up to `times` times) until the target is on screen: the
    /// reader's pages, turned until its closing page shows.
    case swipeUntil(Target, Direction, times: Int)
    /// Waits until the target exists.
    case wait(Target, timeout: Double)
    /// Waits until the target is gone.
    case waitGone(Target, timeout: Double)
    /// Fails unless the target exists (after waiting a little for it).
    case expect(Target)
    /// Turns the device; on an iPad only, and skipped elsewhere.
    case rotate(UIDeviceOrientation)
    /// Turns the device, a phone too (a walk that looks at landscape on purpose).
    case turn(UIDeviceOrientation)
    /// Goes back one screen: the navigation bar's first button, or the edge swipe.
    case back
    /// The interactive back swipe: drags slowly from the leading edge of the top screen's
    /// column (on an iPad, the side pane's when it shows), holds still and lets go, so the
    /// finger has no speed left. Where it lets go decides: `.whole` pops the screen, and
    /// `.letGoEarly` stops 80 pt from the edge, where the system cancels the pop. (The system
    /// goes by distance rather than by a share of the width: on a 13-inch iPad a quarter of
    /// the width, 258 pt, already pops, an eighth does not; on a phone a quarter does not.)
    case backSwipe(BackSwipe)

    enum BackSwipe: String, Sendable {
        case letGoEarly, whole
    }
    case pause(seconds: Double)
    /// A screenshot with this name, attached to the result and exported by `run_walks.sh`.
    case screenshot(String)
    /// The accessibility tree of the screen, attached as text: what a walk's targets can name.
    case dump(String)
    /// XCUITest's accessibility audit of the screen (`performAccessibilityAudit()`), attached as
    /// text with one line per issue. A survey: issues are noted and never fail the walk.
    case audit(String)
    /// The first steps if the target shows up within `within` seconds, otherwise the second:
    /// where designs or devices differ (a menu on one, a row on the other).
    case ifPresent(Target, within: Double, then: [Step], else: [Step])
    /// Named steps, reported as "name › step".
    case group(String, [Step])
    /// Steps whose failure is noted but does not fail the walk.
    case optional([Step])
    /// Steps run only on an iPad, or only on a phone.
    case onPad([Step])
    case onPhone([Step])

    enum Direction: String, Sendable {
        case up, down, left, right
    }

    /// The default wait for an element.
    static let patience: Double = 20

    static func wait(_ target: Target) -> Step { .wait(target, timeout: patience) }

    static func group(_ name: String, _ steps: Step...) -> Step { .group(name, steps) }

    static func tapIfPresent(_ target: Target) -> Step { .tapIfPresent(target, within: 2) }

    var name: String {
        switch self {
        case .launch(let extra): extra.isEmpty ? "launch" : "launch \(extra.joined(separator: " "))"
        case .terminate: "terminate"
        case .tap(let target): "tap \(target)"
        case .tapIfPresent(let target, _): "tap \(target) if present"
        case .tapPoint(let x, let y): "tap at \(x), \(y)"
        case .longPress(let target, let seconds): "long-press \(target) for \(seconds) s"
        case .drag(let target, let dx, let dy): "drag \(target) by \(Int(dx)), \(Int(dy))"
        case .swipe(let direction, let target): "swipe \(direction.rawValue)" + (target.map { " on \($0)" } ?? "")
        case .scroll(let direction, let screens, let target):
            "scroll \(direction.rawValue) \(screens) screens" + (target.map { " on \($0)" } ?? "")
        case .pinch(let scale, let target): "pinch \(scale)" + (target.map { " on \($0)" } ?? "")
        case .type(let text, let target): "type “\(text)”" + (target.map { " into \($0)" } ?? "")
        case .scrollColumn(let direction, let screens): "scroll \(direction) \(screens) screens in the last column"
        case .scrollTo(let target, _): "scroll to \(target)"
        case .swipeUntil(let target, let direction, _): "swipe \(direction.rawValue) until \(target)"
        case .wait(let target, _): "wait for \(target)"
        case .waitGone(let target, _): "wait until \(target) is gone"
        case .expect(let target): "expect \(target)"
        case .rotate(let orientation): "rotate to \(orientation.walkName)"
        case .turn(let orientation): "turn to \(orientation.walkName)"
        case .back: "back"
        case .backSwipe(let swipe): swipe == .whole ? "back swipe" : "back swipe, let go early"
        case .pause(let seconds): "pause \(seconds) s"
        case .screenshot(let name): "screenshot \(name)"
        case .dump(let name): "dump \(name)"
        case .audit(let name): "audit \(name)"
        case .ifPresent(let target, _, _, _): "if \(target)"
        case .group(let name, _): name
        case .optional: "optional"
        case .onPad: "on iPad"
        case .onPhone: "on iPhone"
        }
    }
}

extension UIDeviceOrientation {
    var walkName: String {
        switch self {
        case .portrait: "portrait"
        case .portraitUpsideDown: "portrait upside down"
        case .landscapeLeft: "landscape left"
        case .landscapeRight: "landscape right"
        default: "orientation \(rawValue)"
        }
    }
}
