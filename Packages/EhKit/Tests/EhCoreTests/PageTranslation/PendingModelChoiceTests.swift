import EhModels
import Foundation
import Testing
@testable import EhCore

/// A model chosen while it was not installed, looked at again before the models are picked.
@Suite @MainActor struct PendingModelChoiceTests {
    @Test func theRule() {
        let progress = ModelTransferProgress(completedBytes: 1, totalBytes: 2)
        #expect(PendingModelChoice.verdict(isCurrent: false, state: .installed) == .apply)
        for state in [ModelArtifactState.waiting, .downloading(progress), .paused(progress), .installing, .preparing] {
            #expect(PendingModelChoice.verdict(isCurrent: false, state: state) == .wait)
        }
        #expect(PendingModelChoice.verdict(isCurrent: false, state: .missing) == .forget)
        #expect(PendingModelChoice.verdict(isCurrent: false, state: .failed(.checksumMismatch)) == .forget)
        // Already the choice, or a choice that needs no model.
        #expect(PendingModelChoice.verdict(isCurrent: true, state: .installed) == .forget)
        #expect(PendingModelChoice.verdict(isCurrent: true, state: .downloading(progress)) == .forget)
        #expect(PendingModelChoice.verdict(isCurrent: false, state: nil) == .forget)
    }

    static func store(_ settings: SettingsStore, installed: [ModelArtifactID]) -> PageTranslationModelStore {
        let store = PageTranslationModelStore(environment: .offline(), choices: .settings(settings))
        for id in installed {
            store.states[id] = .installed
            store.records[id] = InstalledArtifact(
                catalogVersion: store.catalog.version, artifact: id, version: "1", items: [], bytes: 1, isPrepared: true
            )
        }
        return store
    }

    @Test func aChoiceWhoseModelIsInstalledBecomesTheChoice() {
        let settings = SettingsStore(storage: .ephemeral())
        settings.pageTranslationPendingDetector = .yolo26s
        settings.pageTranslationPendingRepaint = .bigLama
        let store = Self.store(settings, installed: [.k2xl, .yolo26s, .cpt2, .jmtFast1, .lamaManga, .bigLama])

        store.applyPendingChoices(in: settings)

        #expect(settings.pageTranslationDetector == .yolo26s && settings.pageTranslationPendingDetector == nil)
        #expect(settings.pageTranslationRepaint == .bigLama && settings.pageTranslationPendingRepaint == nil)
        #expect(store.resolvedModelSet?.detector == .yolo26s)
    }

    @Test func aChoiceStillOnItsWayIsLeftAlone() {
        let settings = SettingsStore(storage: .ephemeral())
        settings.pageTranslationPendingReader = .narSmall
        settings.pageTranslationPendingDetector = .v4s
        let store = Self.store(settings, installed: [.k2xl, .cpt2, .jmtFast1])
        store.states[.narSmall] = .downloading(ModelTransferProgress(completedBytes: 1, totalBytes: 2))
        store.states[.v4s] = .preparing

        store.applyPendingChoices(in: settings)

        #expect(settings.pageTranslationReader == .cpt2 && settings.pageTranslationPendingReader == .narSmall)
        #expect(settings.pageTranslationDetector == .k2xl && settings.pageTranslationPendingDetector == .v4s)
    }

    @Test func aChoiceThatCannotBeAppliedIsForgotten() {
        let settings = SettingsStore(storage: .ephemeral())
        settings.pageTranslationPendingDetector = .rtmdet2       // its download failed
        settings.pageTranslationPendingReader = .cpt2            // the choice already
        settings.pageTranslationPendingTranslator = .hyMT2       // missing
        settings.pageTranslationPendingRepaint = .off            // needs no model
        let store = Self.store(settings, installed: [.k2xl, .cpt2, .jmtFast1, .lamaManga])
        store.states[.rtmdet2] = .failed(.unreachable)

        store.applyPendingChoices(in: settings)

        #expect(settings.pageTranslationPendingDetector == nil && settings.pageTranslationDetector == .k2xl)
        #expect(settings.pageTranslationPendingReader == nil && settings.pageTranslationReader == .cpt2)
        #expect(settings.pageTranslationPendingTranslator == nil && settings.pageTranslationTranslator == .jmtFast1)
        #expect(settings.pageTranslationPendingRepaint == nil && settings.pageTranslationRepaint == .lamaManga)
    }
}
