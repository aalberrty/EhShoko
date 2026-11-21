import EhModels
import EhPageTranslation
import Foundation

/// How much of a reader's window the service works on.
///
/// The pages on screen are always worked on. How far ahead it goes depends on what a page
/// costs with the chosen translator and on the state of the phone. The rules are pure, so
/// they are tested as a table.
public struct PageTranslationPolicy: Sendable, Equatable {
    /// How many of the window's pages ahead are worked on.
    public var pagesAhead: Int
    /// Whether the page before is worked on.
    public var includesPageBehind: Bool

    public init(pagesAhead: Int, includesPageBehind: Bool) {
        self.pagesAhead = pagesAhead
        self.includesPageBehind = includesPageBehind
    }

    /// Only the pages on screen.
    public static let onScreenOnly = PageTranslationPolicy(pagesAhead: 0, includesPageBehind: false)

    /// The pages ahead a translator is given when nothing holds it back: three with the Core
    /// ML translator, which finishes a page in under a second, and one with a language model,
    /// which takes 6 to 15 seconds a page and heats the phone within a few pages.
    public static func pagesAhead(for translator: TranslatorChoice) -> Int {
        switch translator.engine {
        case .coreML: 3
        case .languageModel: 1
        }
    }

    /// The policy for a translator and the phone's state.
    ///
    /// - At thermal "serious" or above: only the pages on screen.
    /// - After a memory warning, until the reader moves: only the pages on screen.
    /// - In Low Power Mode: one page ahead at most, and not the page before.
    public static func current(
        translator: TranslatorChoice, heat: PageTranslationHeat, isLowPowerModeEnabled: Bool,
        isUnderMemoryPressure: Bool
    ) -> PageTranslationPolicy {
        if heat >= .serious || isUnderMemoryPressure { return .onScreenOnly }
        let ahead = pagesAhead(for: translator)
        if isLowPowerModeEnabled { return PageTranslationPolicy(pagesAhead: min(ahead, 1), includesPageBehind: false) }
        return PageTranslationPolicy(pagesAhead: ahead, includesPageBehind: true)
    }

    /// The pages of `window` that are worked on, in order of priority.
    public func pages(of window: PageTranslationWindow) -> [PageTranslationPage] {
        var seen = Set<Int>()
        let wanted = window.onScreen + Array(window.ahead.prefix(pagesAhead)) + (includesPageBehind ? window.behind : [])
        return wanted.filter { seen.insert($0.index).inserted }
    }
}

/// The phone's thermal state, as `ProcessInfo` reports it.
public enum PageTranslationHeat: Int, Sendable, Comparable, CaseIterable {
    case nominal, fair, serious, critical

    public init(_ state: ProcessInfo.ThermalState) {
        switch state {
        case .nominal: self = .nominal
        case .fair: self = .fair
        case .serious: self = .serious
        case .critical: self = .critical
        @unknown default: self = .serious
        }
    }

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}
