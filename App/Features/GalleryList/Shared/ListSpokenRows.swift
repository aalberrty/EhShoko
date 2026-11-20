import Foundation

/// Whether a list's rows read their words in full: while VoiceOver is on. Building that line
/// costs every row, so a list asks once per screen (`\.accessibilityVoiceOverEnabled`) and
/// hands the answer to its rows in their style.
nonisolated enum ListSpokenRows {
    static func isOn(_ isVoiceOverOn: Bool) -> Bool {
        #if DEBUG || HARNESS
        if isForced { return true }
        #endif
        return isVoiceOverOn
    }

    #if DEBUG || HARNESS
    /// `-HarnessSpokenRows YES`: the rows build their spoken line without VoiceOver, so that the
    /// accessibility tree shows it where VoiceOver cannot run (a simulator, a walk).
    private static let isForced = UserDefaults.standard.bool(forKey: "HarnessSpokenRows")
    #endif
}
