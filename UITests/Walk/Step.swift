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
    case swipe(Direction, on: Target?)
    /// Drags the content by `screens` window heights (or widths), slowly enough that it does
    /// not fling, so a scroll goes as far as asked.
    case scroll(Direction, screens: Double, on: Target?)
    /// Pinches the target, or the middle of the window: below 1 together, above 1 apart.
    case pinch(scale: Double, on: Target?)
    /// Types into the target, or into whatever has the keyboard focus.
    case type(String, into: Target?)
    /// Scrolls down (up to `screens` times) until the target is on screen: rows of a lazy
    /// list exist only once they are near it.
    case scrollTo(Target, screens: Int)
    /// Waits until the target exists.
    case wait(Target, timeout: Double)
    /// Waits until the target is gone.
    case waitGone(Target, timeout: Double)
    /// Fails unless the target exists (after waiting a little for it).
    case expect(Target)
    /// Turns the device; on an iPad only, and skipped elsewhere.
    case rotate(UIDeviceOrientation)
    /// Goes back one screen: the navigation bar's first button, or the edge swipe.
    case back
    case pause(seconds: Double)
    /// A screenshot with this name, attached to the result and exported by `run_walks.sh`.
    case screenshot(String)
    /// The accessibility tree of the screen, attached as text: what a walk's targets can name.
    case dump(String)
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
        case .swipe(let direction, let target): "swipe \(direction.rawValue)" + (target.map { " on \($0)" } ?? "")
        case .scroll(let direction, let screens, let target):
            "scroll \(direction.rawValue) \(screens) screens" + (target.map { " on \($0)" } ?? "")
        case .pinch(let scale, let target): "pinch \(scale)" + (target.map { " on \($0)" } ?? "")
        case .type(let text, let target): "type “\(text)”" + (target.map { " into \($0)" } ?? "")
        case .scrollTo(let target, _): "scroll to \(target)"
        case .wait(let target, _): "wait for \(target)"
        case .waitGone(let target, _): "wait until \(target) is gone"
        case .expect(let target): "expect \(target)"
        case .rotate(let orientation): "rotate to \(orientation.walkName)"
        case .back: "back"
        case .pause(let seconds): "pause \(seconds) s"
        case .screenshot(let name): "screenshot \(name)"
        case .dump(let name): "dump \(name)"
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
