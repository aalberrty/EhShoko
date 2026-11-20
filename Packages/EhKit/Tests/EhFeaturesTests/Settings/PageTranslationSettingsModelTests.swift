import EhCore
import EhFeatures
import EhModels
import Foundation
import Testing

@Suite struct PageTranslationSettingsModelTests {
    // MARK: Choosing

    @Test func choosingAnInstalledModelAppliesAtOnce() async throws {
        let harness = TranslationStoreHarness()
        try harness.copyIn([.v4s])
        try await harness.installDefaultSet()
        let model = harness.makeModel()
        await model.load()
        let before = harness.transport.requests.count

        await model.choose(.detector(.v4s))

        #expect(harness.settings.pageTranslationDetector == .v4s)
        #expect(model.current(.detector) == .detector(.v4s))
        #expect(model.pending.isEmpty)
        #expect(harness.transport.requests.count == before)
        #expect(model.setState == .ready)
    }

    @Test func choosingAMissingModelDownloadsItAndAppliesOnceInstalled() async throws {
        let harness = TranslationStoreHarness()
        try await harness.installDefaultSet()
        harness.hold(.galTransl4B)
        let model = harness.makeModel()
        await model.load()

        await model.choose(.translator(.galTransl4B))

        // The current translator keeps working while the other one downloads.
        #expect(harness.settings.pageTranslationTranslator == .jmtFast1)
        #expect(model.pending[.translator] == .translator(.galTransl4B))
        #expect(model.setState == .ready)
        await waitFor("the language model is being fetched") { harness.isWaiting(.galTransl4B) }
        let card = try #require(model.cards(for: .translator).first { $0.choice == .translator(.galTransl4B) })
        #expect(card.isPending)
        #expect(!card.isSelected)
        guard case .downloading = card.availability else {
            Issue.record("A pending model's card shows its download, not \(card.availability)")
            return
        }

        harness.release(.galTransl4B)
        await waitFor("the language model is chosen") { harness.settings.pageTranslationTranslator == .galTransl4B }
        #expect(harness.store.state(of: .galTransl4B) == .installed)
        #expect(model.pending.isEmpty)
        #expect(model.cards(for: .translator).first { $0.isSelected }?.choice == .translator(.galTransl4B))
    }

    @Test func aChoiceAppliesWhenItsInstallFinishesAfterTheScreenClosed() async throws {
        let harness = TranslationStoreHarness()
        try await harness.installDefaultSet()
        harness.hold(.v4s)
        weak var released: PageTranslationSettingsModel?
        do {
            let model = harness.makeModel()
            released = model
            await model.load()
            await model.choose(.detector(.v4s))
        }
        await waitFor("the detector is being fetched") { harness.isWaiting(.v4s) }
        // The watch keeps the model while its choice waits.
        #expect(released != nil)

        harness.release(.v4s)
        await waitFor("the detector is chosen") { harness.settings.pageTranslationDetector == .v4s }
        await waitFor("the model is released once nothing waits") { released == nil }
    }

    @Test func choosingWhileNothingIsInstalledAppliesAtOnceAndFetchesNothing() async {
        let harness = TranslationStoreHarness()
        let model = harness.makeModel()
        await model.load()

        await model.choose(.detector(.v4s))

        #expect(harness.settings.pageTranslationDetector == .v4s)
        #expect(model.pending.isEmpty)
        #expect(harness.transport.requests.isEmpty)
        let set: [ModelArtifactID] = [.v4s, .cpt2, .jmtFast1, .lamaManga]
        #expect(model.topAction == .download(bytes: set.reduce(0) { $0 + TranslationSamples.size(of: $1) }))
    }

    @Test func aModelChosenWhileTheSetDownloadsJoinsTheDownload() async {
        let harness = TranslationStoreHarness()
        harness.hold(.k2xl)
        harness.hold(.cpt2)
        let model = harness.makeModel()
        await model.load()
        model.performTopAction()
        await waitFor("the detector and the reader are being fetched") {
            harness.isWaiting(.k2xl) && harness.isWaiting(.cpt2)
        }

        await model.choose(.detector(.v4s))

        #expect(harness.settings.pageTranslationDetector == .v4s)
        harness.release(.cpt2)
        await waitFor("the new set is ready") { model.setState == .ready }
        // The detector it replaced was not kept.
        #expect(harness.store.state(of: .k2xl) == .missing)
        #expect(!harness.folderExists(of: .k2xl))
    }

    @Test func choosingTheCurrentModelAgainGivesUpTheOneThatWaited() async throws {
        let harness = TranslationStoreHarness()
        try await harness.installDefaultSet()
        harness.hold(.galTransl4B)
        let model = harness.makeModel()
        await model.load()
        await model.choose(.translator(.galTransl4B))
        await waitFor("the language model is being fetched") { harness.isWaiting(.galTransl4B) }

        await model.choose(.translator(.jmtFast1))

        #expect(model.pending.isEmpty)
        #expect(harness.settings.pageTranslationTranslator == .jmtFast1)
        #expect(harness.store.state(of: .galTransl4B) == .missing)
        #expect(!harness.folderExists(of: .galTransl4B))
    }

    @Test func choosingAnotherMissingModelGivesUpTheFirst() async throws {
        let harness = TranslationStoreHarness()
        try await harness.installDefaultSet()
        harness.hold(.v4s)
        harness.hold(.yolo26s)
        let model = harness.makeModel()
        await model.load()
        await model.choose(.detector(.v4s))
        await waitFor("the first detector is being fetched") { harness.isWaiting(.v4s) }

        await model.choose(.detector(.yolo26s))

        #expect(model.pending[.detector] == .detector(.yolo26s))
        #expect(harness.store.state(of: .v4s) == .missing)
        harness.release(.yolo26s)
        await waitFor("the second detector is chosen") { harness.settings.pageTranslationDetector == .yolo26s }
    }

    @Test func aDownloadUnderWayWhenTheScreenOpensIsTakenAsThatChoice() async throws {
        let harness = TranslationStoreHarness()
        try await harness.installDefaultSet()
        harness.hold(.galTransl4B)
        // Asked for on a screen that has closed: the store goes on with it.
        harness.store.download([.galTransl4B])
        await waitFor("the language model is being fetched") { harness.isWaiting(.galTransl4B) }

        let model = harness.makeModel()
        await model.load()

        #expect(model.pending[.translator] == .translator(.galTransl4B))
        harness.release(.galTransl4B)
        await waitFor("the language model is chosen") { harness.settings.pageTranslationTranslator == .galTransl4B }
    }

    @Test func aChoiceTheSourcesCannotProvideIsListedAndCannotBeChosen() async {
        let harness = TranslationStoreHarness(privateStore: false)
        let model = harness.makeModel()
        await model.load()

        let cards = model.cards(for: .detector)
        #expect(cards.map(\.choice) == [.detector(.k2xl), .detector(.yolo26s), .detector(.v4s)])
        let koharu = cards[0]
        #expect(koharu.availability == .notOffered)
        #expect(!koharu.canBeChosen)
        #expect(koharu.isPrivateOnly)
        // The public detector is missing only because there is no public store: its licence
        // is not the reason.
        #expect(cards[2].availability == .notOffered)
        #expect(!cards[2].isPrivateOnly)
        #expect(koharu.figureGroups.flatMap(\.figures) == PageTranslationMeasurements.figures(for: .k2xl))

        await model.choose(.detector(.k2xl))
        await model.choose(.detector(.yolo26s))

        #expect(harness.settings.pageTranslationDetector == .k2xl)
        #expect(harness.transport.requests.isEmpty)
        // Without any source nothing can be had, and the screen says a source is needed.
        #expect(model.setState == .unavailable)
        #expect(model.topAction == nil)
    }

    @Test func defaultIsTheBestModelTheSourcesOffer() async throws {
        // Without a private store, only the public detector can be had once it is installed.
        let harness = TranslationStoreHarness(privateStore: false)
        try harness.copyIn([.v4s])
        let model = harness.makeModel()
        await model.load()
        await waitFor("the copied detector is installed") { harness.store.state(of: .v4s) == .installed }

        let cards = model.cards(for: .detector)
        #expect(cards.filter(\.isDefault).map(\.choice) == [.detector(.v4s)])
        #expect(cards.filter(\.isSelected).map(\.choice) == [.detector(.v4s)])
        #expect(model.current(.detector) == .detector(.v4s))
    }

    // MARK: The four kinds

    @Test func everyKindListsTheChoicesOfTheCatalog() async {
        let harness = TranslationStoreHarness()
        let model = harness.makeModel()
        await model.load()

        #expect(model.cards(for: .reader).map(\.choice) == [.reader(.cpt2)])
        #expect(model.cards(for: .translator).map(\.choice) == [.translator(.jmtFast1), .translator(.galTransl4B)])
        // Off needs no model, so it is always there.
        #expect(model.cards(for: .repaint).map(\.choice) == [.repaint(.off), .repaint(.lamaManga)])
        #expect(model.cards(for: .repaint).first?.availability == .noDownload)
        for role in ModelRole.allCases {
            let cards = model.cards(for: role)
            #expect(cards.filter(\.isSelected).count == 1)
            #expect(cards.filter(\.isDefault).count == 1)
            for card in cards {
                #expect(card.figureGroups == MeasuredFigureGroup.grouping(card.choice.figures))
            }
        }
        let needs = model.cards(for: .reader).first?.availability
        #expect(needs == .needs(bytes: TranslationSamples.size(of: .cpt2)))
    }

    @Test func eachKindChoosesItsOwnSetting() async throws {
        let harness = TranslationStoreHarness()
        try harness.copyIn([.yolo26s, .galTransl4B])
        try await harness.installDefaultSet()
        let model = harness.makeModel()
        await model.load()

        await model.choose(.detector(.yolo26s))
        await model.choose(.translator(.galTransl4B))
        await model.choose(.repaint(.off))
        await model.choose(.reader(.cpt2))

        #expect(harness.settings.pageTranslationModelSet == PageTranslationModelSet(
            detector: .yolo26s, reader: .cpt2, translator: .galTransl4B
        ))
        #expect(harness.settings.pageTranslationRepaint == .off)
        #expect(harness.store.requiredArtifacts == [.yolo26s, .cpt2, .galTransl4B])
    }

    @Test func figuresAreGroupedByWhatTheyWereMeasuredOn() {
        let detector = MeasuredFigureGroup.grouping(PageTranslationMeasurements.figures(for: TextDetectorChoice.rtmdet2))
        #expect(detector.map(\.basis) == [.pagesMac, .phone])
        #expect(detector.map(\.figures.count) == [2, 3])
        let translator = MeasuredFigureGroup.grouping(PageTranslationMeasurements.figures(for: TranslatorChoice.hyMT2))
        #expect(translator.map(\.basis) == [.pagesMac, .phone])
        #expect(translator[0].figures.allSatisfy { $0.note == .largerFile })
        let off = MeasuredFigureGroup.grouping(PageTranslationMeasurements.figures(for: RepaintChoice.off))
        #expect(off.map(\.basis) == [.phone])
        #expect(off[0].figures.map(\.value) == [.notMeasured])

        // A basis that comes back starts a group of its own: the table's order stays.
        let mixed = [
            MeasuredFigure(kind: .memory, value: .megabytes(1), basis: .phone),
            MeasuredFigure(kind: .linesReadExactly, value: .tally(1, of: 2), basis: .pagesMac),
            MeasuredFigure(kind: .firstLoad, value: .seconds(1), basis: .phone)
        ]
        #expect(MeasuredFigureGroup.grouping(mixed).map(\.basis) == [.phone, .pagesMac, .phone])
        #expect(MeasuredFigureGroup.grouping([]).isEmpty)
    }

    // MARK: The top card

    @Test func thePairLineIsTheCurrentDetectorAndReader() async throws {
        let harness = TranslationStoreHarness()
        try harness.copyIn([.v4s])
        try await harness.installDefaultSet()
        let model = harness.makeModel()
        await model.load()
        #expect(model.pair.value == .tally(115, of: 149))

        await model.choose(.detector(.v4s))

        #expect(model.pair.value == .notMeasured)
    }

    @Test func theTopCardDownloadsPausesAndResumesTheSet() async {
        let harness = TranslationStoreHarness()
        harness.hold(.jmtFast1)
        let model = harness.makeModel()
        await model.load()
        let total: Int64 = [ModelArtifactID.k2xl, .cpt2, .jmtFast1, .lamaManga]
            .reduce(0) { $0 + TranslationSamples.size(of: $1) }
        #expect(model.setState == .missing(bytes: total))
        #expect(model.topAction == .download(bytes: total))

        #expect(!model.canDeleteAll)
        model.performTopAction()
        await waitFor("the translator is being fetched") { harness.isWaiting(.jmtFast1) }
        #expect(model.topAction == .pause)
        #expect(model.canDeleteAll)

        model.performTopAction()
        await waitFor("the download is paused") { model.topAction == .resume }
        guard case .paused = model.setState else {
            Issue.record("Expected a paused set, got \(model.setState)")
            return
        }

        harness.release(.jmtFast1)
        model.performTopAction()
        await waitFor("the set is ready") { model.setState == .ready }
        #expect(model.topAction == nil)
    }
}
