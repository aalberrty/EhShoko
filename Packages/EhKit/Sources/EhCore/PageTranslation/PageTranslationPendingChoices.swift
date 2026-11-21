import EhModels
import Foundation

/// What becomes of a model that was chosen while it was not installed.
///
/// Such a choice waits in the settings (`pageTranslationPending…`) while the current models
/// keep working. It is looked at again whenever someone is about to rely on the choices: the
/// Translation screen when it loads, and the translation service before it picks its models.
/// Both ask this one rule.
public enum PendingModelChoice: Sendable, Equatable {
    /// Its model is installed: it becomes the choice and stops waiting.
    case apply
    /// Its model is still on its way: both the choice and the wait stay as they are.
    case wait
    /// It is the current choice already, it needs no model, or its download ended without an
    /// install: it stops waiting. Choosing it again tries again.
    case forget

    /// - Parameters:
    ///   - isCurrent: whether the waiting choice is the one in use.
    ///   - state: where its model stands; `nil` for a choice that needs none.
    public static func verdict(isCurrent: Bool, state: ModelArtifactState?) -> PendingModelChoice {
        guard !isCurrent, let state else { return .forget }
        switch state {
        case .installed: return .apply
        case .waiting, .downloading, .paused, .installing, .preparing: return .wait
        case .missing, .failed: return .forget
        }
    }
}

extension PageTranslationModelStore {
    /// Looks at the four waiting choices of `settings` and applies or forgets each as
    /// `PendingModelChoice` says. Call it after `refresh()`, so the states are those of the
    /// folder as it is.
    public func applyPendingChoices(in settings: SettingsStore) {
        if let pending = settings.pageTranslationPendingDetector {
            let current = resolvedDetector ?? settings.pageTranslationDetector
            switch PendingModelChoice.verdict(isCurrent: pending == current, state: state(of: pending.artifact)) {
            case .apply:
                settings.pageTranslationPendingDetector = nil
                settings.pageTranslationDetector = pending
            case .forget: settings.pageTranslationPendingDetector = nil
            case .wait: break
            }
        }
        if let pending = settings.pageTranslationPendingReader {
            let current = resolvedReader ?? settings.pageTranslationReader
            switch PendingModelChoice.verdict(isCurrent: pending == current, state: state(of: pending.artifact)) {
            case .apply:
                settings.pageTranslationPendingReader = nil
                settings.pageTranslationReader = pending
            case .forget: settings.pageTranslationPendingReader = nil
            case .wait: break
            }
        }
        if let pending = settings.pageTranslationPendingTranslator {
            let current = resolvedTranslator ?? settings.pageTranslationTranslator
            switch PendingModelChoice.verdict(isCurrent: pending == current, state: state(of: pending.artifact)) {
            case .apply:
                settings.pageTranslationPendingTranslator = nil
                settings.pageTranslationTranslator = pending
            case .forget: settings.pageTranslationPendingTranslator = nil
            case .wait: break
            }
        }
        if let pending = settings.pageTranslationPendingRepaint {
            let state = pending.artifact.map(state(of:))
            switch PendingModelChoice.verdict(isCurrent: pending == resolvedRepaint, state: state) {
            case .apply:
                settings.pageTranslationPendingRepaint = nil
                settings.pageTranslationRepaint = pending
            case .forget: settings.pageTranslationPendingRepaint = nil
            case .wait: break
            }
        }
    }
}
