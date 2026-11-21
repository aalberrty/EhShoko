import EhCore
import EhModels

// A pending choice kept across launches. The model writes `pending` to the settings as it
// changes; when the Translation screen loads, a choice kept from an earlier launch is applied
// when its model was installed meanwhile, waited for when its download goes on, and
// forgotten when its download ended without an install.

extension PageTranslationSettingsModel {
    /// The pending choice of a kind as the settings keep it.
    func persistedPending(_ role: ModelRole) -> PageTranslationChoice? {
        switch role {
        case .detector: settings.pageTranslationPendingDetector.map(PageTranslationChoice.detector)
        case .reader: settings.pageTranslationPendingReader.map(PageTranslationChoice.reader)
        case .translator: settings.pageTranslationPendingTranslator.map(PageTranslationChoice.translator)
        case .repaint: settings.pageTranslationPendingRepaint.map(PageTranslationChoice.repaint)
        }
    }

    /// Writes the kinds whose pending choice changed. A kind that did not change is left as
    /// the settings have it, so a choice kept from an earlier launch is not lost before
    /// `restorePendingChoices()` has looked at it.
    func persistPending(changedFrom old: [ModelRole: PageTranslationChoice]) {
        for role in ModelRole.allCases where pending[role] != old[role] {
            persist(pending[role], for: role)
        }
    }

    private func persist(_ choice: PageTranslationChoice?, for role: ModelRole) {
        switch role {
        case .detector:
            settings.pageTranslationPendingDetector = if case .detector(let detector) = choice { detector } else { nil }
        case .reader:
            settings.pageTranslationPendingReader = if case .reader(let reader) = choice { reader } else { nil }
        case .translator:
            settings.pageTranslationPendingTranslator =
                if case .translator(let translator) = choice { translator } else { nil }
        case .repaint:
            settings.pageTranslationPendingRepaint = if case .repaint(let repaint) = choice { repaint } else { nil }
        }
    }

    /// Takes up the choices the settings kept from an earlier launch, once the store has
    /// looked at its folder. The watch that applies them starts with `adoptDownloadsUnderWay()`.
    func restorePendingChoices() {
        for role in ModelRole.allCases where pending[role] == nil {
            guard let choice = persistedPending(role) else { continue }
            // The rule is the store's, which the translation service asks too.
            let state = choice.artifact.map { store.state(of: $0) }
            switch PendingModelChoice.verdict(isCurrent: choice == current(role), state: state) {
            case .apply:
                persist(nil, for: role)
                apply(choice)
            case .wait:
                pending[role] = choice
            case .forget:
                // Current already, or the download ended without an install; choosing it
                // again tries again.
                persist(nil, for: role)
            }
        }
    }
}
