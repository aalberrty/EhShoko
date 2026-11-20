import Dependencies
import EhCore
import EhModels
import Observation

/// The setup wizard (`Route.settings(.designSetup)`): a preset or the current choices as the
/// starting point, then one step per page, then a summary with "Apply".
///
/// It works on a draft. The draft starts as the choices the app uses (or as a preset the
/// caller passes), every step edits it and every preview is drawn from it; nothing is written
/// until `apply()`, which assigns `SettingsStore.designChoices` once. Leaving without applying
/// forgets the draft and changes no setting.
///
/// Browsing is reset by the shell, which watches the bar and the first screen: one assignment
/// changes each at most once, so a wizard that changes either resets browsing once, and one
/// that changes neither leaves it alone.
@Observable
public final class DesignSetupModel {
    /// Where the wizard is.
    nonisolated public enum Step: Hashable, Sendable {
        /// Step 1: start from a preset, or keep what the app has.
        case start
        /// One page's options.
        case part(DesignPart)
        /// The result, with "Apply".
        case summary
    }

    /// The draft as the "So far" line and the summary name it.
    nonisolated public enum DraftState: Equatable, Sendable {
        /// The draft is a preset: "Shelf".
        case preset(DesignStyle)
        /// A preset with another look and nothing else changed: "Shelf with Ledger's colours".
        case presetWithLook(DesignStyle, look: DesignStyle)
        /// Anything else: "Custom", with the pages that differ from the nearest preset.
        case custom(changed: [DesignPart], from: DesignStyle)
    }

    /// The pages the wizard asks about, in its order: colours and type first, because every
    /// later preview is drawn in what is chosen there, then the others as
    /// `DesignPart.choosable` lists them. Generated from `choosable`, so a page that leaves it
    /// leaves the wizard.
    public static let parts: [DesignPart] = {
        let choosable = DesignPart.choosable
        return choosable.filter { $0 == .look } + choosable.filter { $0 != .look }
    }()

    /// The number of steps the wizard counts: the start and one per page. The summary is not
    /// counted.
    public static var stepCount: Int { parts.count + 1 }

    /// The choices every preview of the wizard is drawn from and "Apply" writes.
    public var draft: DesignChoices { edited ?? startingChoices }
    public private(set) var step: Step = .start
    /// The preset chosen on step 1, or `nil` for "Keep what I have".
    public private(set) var startingPoint: DesignStyle?
    /// Whether the step on screen was opened from the summary, so its primary button leads
    /// back there ("Back to summary").
    public private(set) var returnsToSummary = false

    /// The draft once a page was chosen; until then the draft is the starting point itself.
    private var edited: DesignChoices?

    @ObservationIgnored @Dependency(\.settings) private var settings

    /// Reads no setting, so the view that builds the wizard's screen does not observe them.
    ///
    /// - Parameter startingPoint: a preset to start from (the offer's "Set up step by step"
    ///   passes the tile it had selected); `nil` starts from the current choices.
    public init(startingPoint: DesignStyle? = nil) {
        self.startingPoint = startingPoint
    }

    // MARK: What the wizard shows

    /// The choices the app uses now. Reading it observes all eight design properties, which
    /// only Settings and the wizard may do.
    public var current: DesignChoices { settings.designChoices }

    /// Whether the draft differs from what the app uses: "Apply" writes it, and leaving asks
    /// first and cannot be done with a swipe.
    public var hasChanges: Bool { draft != current }

    /// The step's number for "5 of 9": 1 for the start, 2 and up for the pages, `nil` for the
    /// summary.
    public var stepNumber: Int? {
        switch step {
        case .start: 1
        case .part(let part): (Self.parts.firstIndex(of: part) ?? 0) + 2
        case .summary: nil
        }
    }

    public var draftState: DraftState { Self.state(of: draft) }

    /// Whether choosing on step 1 would replace choices made in later steps: the draft is no
    /// longer what the starting point set it to. A line under the tiles says so.
    public var replacesLaterChoices: Bool { draft != startingChoices }

    /// Whether `part`'s choice in the draft differs from the one the app uses now; the
    /// summary marks it in the tint.
    public func differsFromCurrent(_ part: DesignPart) -> Bool {
        draft[part] != current[part]
    }

    // MARK: Choosing

    /// Step 1: sets the whole draft to `preset`, or back to the current choices for `nil`
    /// ("Keep what I have"). Choices made in later steps are replaced.
    public func selectStartingPoint(_ preset: DesignStyle?) {
        startingPoint = preset
        edited = nil
    }

    /// A page's step: sets that page's choice in the draft.
    public func select(_ option: DesignOption, for part: DesignPart) {
        var choices = draft
        choices[part] = option
        edited = choices
    }

    // MARK: Moving

    /// The following step: from the start the first page, from a page the next one, from the
    /// last page the summary. A step opened from the summary goes back to it.
    public func next() {
        switch step {
        case .start:
            if returnsToSummary {
                showSummary()
            } else if let first = Self.parts.first {
                step = .part(first)
            } else {
                showSummary()
            }
        case .part(let part):
            if !returnsToSummary, let following = Self.part(after: part) {
                step = .part(following)
            } else {
                showSummary()
            }
        case .summary:
            break
        }
    }

    /// Leaves the page as the draft has it and goes on, as `next()` does.
    public func skip() {
        next()
    }

    /// The previous step, keeping every choice. Nothing before the start.
    public func back() {
        switch step {
        case .start:
            break
        case .part(let part):
            step = Self.part(before: part).map(Step.part) ?? .start
        case .summary:
            step = Self.parts.last.map(Step.part) ?? .start
        }
    }

    /// From the summary: opens the step of `part`, whose primary button then leads back to
    /// the summary.
    public func jump(to part: DesignPart) {
        guard step == .summary, Self.parts.contains(part) else { return }
        step = .part(part)
        returnsToSummary = true
    }

    // MARK: Applying

    /// Writes the draft in one assignment and returns `true`; returns `false` and writes
    /// nothing when the draft equals the current choices (the button then reads "Done").
    @discardableResult
    public func apply() -> Bool {
        guard hasChanges else { return false }
        settings.designChoices = draft
        return true
    }

    // MARK: Helpers

    private var startingChoices: DesignChoices {
        startingPoint.map(DesignChoices.init(preset:)) ?? current
    }

    private func showSummary() {
        step = .summary
        returnsToSummary = false
    }

    private static func part(after part: DesignPart) -> DesignPart? {
        guard let index = parts.firstIndex(of: part), index + 1 < parts.count else { return nil }
        return parts[index + 1]
    }

    private static func part(before part: DesignPart) -> DesignPart? {
        guard let index = parts.firstIndex(of: part), index > 0 else { return nil }
        return parts[index - 1]
    }

    /// A set of choices as the wizard names it.
    public nonisolated static func state(of choices: DesignChoices) -> DraftState {
        if let preset = choices.preset {
            return .preset(preset)
        }
        let nearest = choices.nearestPreset
        let changed = choices.differences(from: nearest)
        if changed == [.look] {
            return .presetWithLook(nearest, look: choices.look)
        }
        return .custom(changed: changed, from: nearest)
    }
}
