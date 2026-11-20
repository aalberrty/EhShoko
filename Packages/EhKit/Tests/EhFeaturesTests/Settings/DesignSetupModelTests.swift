import Dependencies
@testable import EhCore
import EhFeatures
import EhModels
import EhTestSupport
import Foundation
import Observation
import Testing

@MainActor @Suite struct DesignSetupModelTests {
    // MARK: The draft

    @Test func theDraftStartsAsTheCurrentChoices() {
        let (store, _) = Self.store(with: Self.mix)
        let model = Self.model(store)
        #expect(model.draft == Self.mix)
        #expect(model.current == Self.mix)
        #expect(model.step == .start)
        #expect(model.startingPoint == nil)
        #expect(!model.hasChanges)
    }

    @Test func aStartingPresetFromOutsideStartsTheDraftThere() {
        let (store, writes) = Self.store()
        let model = Self.model(store, startingPoint: .ledger)
        #expect(model.startingPoint == .ledger)
        #expect(model.draft == DesignChoices(preset: .ledger))
        #expect(model.hasChanges)
        #expect(writes.total == 0)
    }

    @Test func aPresetOnStepOneReplacesTheDraftAndKeepRestoresIt() {
        let (store, _) = Self.store(with: Self.mix)
        let model = Self.model(store)
        model.selectStartingPoint(.wall)
        #expect(model.startingPoint == .wall)
        #expect(model.draft == DesignChoices(preset: .wall))

        model.next()
        model.select(.style(.ledger), for: .look)
        #expect(model.replacesLaterChoices)
        model.back()
        model.selectStartingPoint(.shelf)
        #expect(model.draft == DesignChoices(preset: .shelf))
        #expect(!model.replacesLaterChoices)

        model.selectStartingPoint(nil)
        #expect(model.startingPoint == nil)
        #expect(model.draft == Self.mix)
        #expect(!model.hasChanges)
    }

    @Test func choosingAPartChangesOnlyThatPartOfTheDraft() {
        let (store, writes) = Self.store()
        let model = Self.model(store)
        model.select(.bar(.command), for: .bar)
        model.select(.style(.ledger), for: .reader)
        var expected = DesignChoices(preset: .shelf)
        expected.bar = .command
        expected.reader = .ledger
        #expect(model.draft == expected)
        #expect(model.differsFromCurrent(.bar))
        #expect(model.differsFromCurrent(.reader))
        #expect(!model.differsFromCurrent(.list))
        #expect(store.designChoices == DesignChoices(preset: .shelf))
        #expect(writes.total == 0)
    }

    // MARK: Moving between steps

    @Test func stepsRunFromTheStartThroughColoursFirstToTheSummary() {
        let (store, _) = Self.store()
        let model = Self.model(store)
        #expect(DesignSetupModel.parts == [.look, .bar, .start, .list, .gallery, .reader, .search, .library])
        #expect(DesignSetupModel.stepCount == 9)
        var visited: [DesignSetupModel.Step] = [model.step]
        var numbers: [Int?] = [model.stepNumber]
        while model.step != .summary {
            model.next()
            visited.append(model.step)
            numbers.append(model.stepNumber)
        }
        #expect(visited == [.start] + DesignSetupModel.parts.map(DesignSetupModel.Step.part) + [.summary])
        #expect(numbers == [1, 2, 3, 4, 5, 6, 7, 8, 9, nil])
        model.next()
        #expect(model.step == .summary)
    }

    @Test func skipChangesNothingAndGoesOn() {
        let (store, _) = Self.store()
        let model = Self.model(store)
        model.next()
        let before = model.draft
        model.skip()
        #expect(model.step == .part(.bar))
        #expect(model.draft == before)
        #expect(!model.hasChanges)
    }

    @Test func backKeepsEveryChoice() {
        let (store, _) = Self.store()
        let model = Self.model(store)
        model.selectStartingPoint(.wall)
        model.next()
        model.select(.style(.ledger), for: .look)
        model.next()
        model.select(.bar(.tabs), for: .bar)
        let draft = model.draft
        model.back()
        #expect(model.step == .part(.look))
        model.back()
        #expect(model.step == .start)
        model.back()
        #expect(model.step == .start)
        #expect(model.draft == draft)
        #expect(model.startingPoint == .wall)
    }

    @Test func backFromTheSummaryOpensTheLastPage() {
        let (store, _) = Self.store()
        let model = Self.model(store)
        Self.walkToSummary(model)
        model.back()
        #expect(model.step == .part(.library))
    }

    @Test func aLineOfTheSummaryOpensItsStepWhichLeadsBack() {
        let (store, _) = Self.store()
        let model = Self.model(store)
        Self.walkToSummary(model)
        model.jump(to: .reader)
        #expect(model.step == .part(.reader))
        #expect(model.returnsToSummary)
        model.select(.style(.wall), for: .reader)
        model.next()
        #expect(model.step == .summary)
        #expect(!model.returnsToSummary)
        #expect(model.draft.reader == .wall)

        model.jump(to: .list)
        model.back()
        #expect(model.step == .part(.start))
        #expect(model.returnsToSummary)
        model.skip()
        #expect(model.step == .summary)
    }

    @Test func jumpingOnlyWorksFromTheSummary() {
        let (store, _) = Self.store()
        let model = Self.model(store)
        model.jump(to: .reader)
        #expect(model.step == .start)
        #expect(!model.returnsToSummary)
    }

    // MARK: The state so far

    @Test func theStateOfAPreset() {
        #expect(DesignSetupModel.state(of: DesignChoices(preset: .ledger)) == .preset(.ledger))
    }

    @Test func theStateOfAChangeOfColoursOnly() {
        var choices = DesignChoices(preset: .shelf)
        choices.look = .ledger
        #expect(DesignSetupModel.state(of: choices) == .presetWithLook(.shelf, look: .ledger))
    }

    @Test func theStateOfACustomMix() {
        #expect(DesignSetupModel.state(of: Self.mix) == .custom(changed: [.list, .reader], from: .shelf))
        var choices = DesignChoices(preset: .wall)
        choices.look = .ledger
        choices.search = .shelf
        #expect(DesignSetupModel.state(of: choices) == .custom(changed: [.search, .look], from: .wall))
    }

    @Test func theModelNamesItsDraft() {
        let (store, _) = Self.store()
        let model = Self.model(store)
        #expect(model.draftState == .preset(.shelf))
        model.select(.style(.wall), for: .look)
        #expect(model.draftState == .presetWithLook(.shelf, look: .wall))
        model.select(.style(.ledger), for: .list)
        #expect(model.draftState == .custom(changed: [.list, .look], from: .shelf))
    }

    // MARK: Applying

    @Test func applyWritesTheDraftOnceInOneAssignment() {
        let (store, writes) = Self.store()
        let model = Self.model(store)
        Self.walkToSummary(model, choosing: [(.list, .style(.ledger)), (.reader, .style(.wall))])
        #expect(writes.total == 0)

        #expect(model.apply())
        #expect(store.designChoices == Self.mix)
        // Each changed part once, and the mix remembered for Custom; nothing else.
        #expect(writes.counts == [.designList: 1, .designReader: 1, .designCustom: 1])
        #expect(!model.hasChanges)

        #expect(!model.apply())
        #expect(writes.total == 3)
    }

    @Test func applyWritesNothingWhenTheDraftIsTheCurrentChoices() {
        let (store, writes) = Self.store(with: Self.mix)
        let model = Self.model(store)
        model.selectStartingPoint(.ledger)
        model.selectStartingPoint(nil)
        Self.walkToSummary(model)
        #expect(!model.hasChanges)
        #expect(!model.apply())
        #expect(writes.total == 0)
        #expect(store.designChoices == Self.mix)
    }

    @Test func applyTouchesTheBarAndTheFirstScreenOnlyWhenTheyChange() {
        // The shell resets browsing when it sees the bar or the first screen change.
        let (store, _) = Self.store()
        let listOnly = Self.model(store)
        listOnly.select(.style(.wall), for: .list)
        let listResets = Self.navigationChanges(in: store) { listOnly.apply() }
        #expect(!listResets)

        let (otherStore, otherWrites) = Self.store()
        let preset = Self.model(otherStore)
        preset.selectStartingPoint(.wall)
        let presetResets = Self.navigationChanges(in: otherStore) { preset.apply() }
        #expect(presetResets)
        #expect(otherWrites.counts[.designBar] == 1)
        #expect(otherWrites.counts[.designStart] == 1)

        let (startStore, _) = Self.store()
        let start = Self.model(startStore)
        start.select(.style(.ledger), for: .start)
        let startResets = Self.navigationChanges(in: startStore) { start.apply() }
        #expect(startResets)
    }

    @Test func leavingWithoutApplyChangesNoSetting() {
        let (store, writes) = Self.store(with: Self.mix)
        var model: DesignSetupModel? = Self.model(store)
        model?.selectStartingPoint(.ledger)
        model?.next()
        model?.select(.style(.wall), for: .look)
        weak let released = model
        model = nil
        #expect(released == nil)
        #expect(writes.total == 0)
        #expect(store.designChoices == Self.mix)
        #expect(store.designCustom == nil)
    }

    // MARK: Helpers

    /// The owner's example of a mix: Shelf with Ledger's lists and Wall's reader.
    private static let mix: DesignChoices = {
        var choices = DesignChoices(preset: .shelf)
        choices.list = .ledger
        choices.reader = .wall
        return choices
    }()

    private static func store(with choices: DesignChoices? = nil) -> (SettingsStore, CountingDefaults) {
        let defaults = CountingDefaults()
        let store = SettingsStore(storage: PreferenceStorage(defaults))
        if let choices {
            store.designChoices = choices
            store.designCustom = nil
            defaults.reset()
        }
        return (store, defaults)
    }

    private static func model(_ store: SettingsStore, startingPoint: DesignStyle? = nil) -> DesignSetupModel {
        withDependencies { $0.settings = store } operation: { DesignSetupModel(startingPoint: startingPoint) }
    }

    private static func walkToSummary(
        _ model: DesignSetupModel, choosing choices: [(DesignPart, DesignOption)] = []
    ) {
        while model.step != .summary {
            if case .part(let part) = model.step, let choice = choices.first(where: { $0.0 == part }) {
                model.select(choice.1, for: part)
            }
            model.next()
        }
    }

    /// Whether `change` changes what the shell resets browsing on: the bar or the first screen.
    private static func navigationChanges(in store: SettingsStore, during change: () -> Void) -> Bool {
        let fired = SettingsTestLock(false)
        withObservationTracking {
            _ = store.designBar
            _ = store.designStart
        } onChange: {
            fired.set(true)
        }
        change()
        return fired.value
    }
}
