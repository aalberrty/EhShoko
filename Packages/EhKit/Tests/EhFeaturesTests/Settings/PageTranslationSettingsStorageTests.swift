import Dependencies
import EhCore
import EhFeatures
import EhModels
import EhTestSupport
import Foundation
import Testing

@Suite struct PageTranslationSettingsStorageTests {
    // MARK: Storage

    @Test func storageListsTheInstalledModelsAndDeletesThem() async throws {
        let harness = TranslationStoreHarness()
        try harness.copyIn([.v4s])
        try await harness.installDefaultSet()
        let model = harness.makeModel()
        await model.load()

        #expect(model.installedModels.map(\.id) == [.k2xl, .v4s, .cpt2, .jmtFast1, .lamaManga])
        #expect(model.installedModels.first?.choice == .detector(.k2xl))
        #expect(model.installedModels.allSatisfy { $0.bytes > 0 })
        #expect(model.installedBytes == model.installedModels.reduce(0) { $0 + $1.bytes })

        await model.delete(.v4s)
        #expect(model.installedModels.map(\.id) == [.k2xl, .cpt2, .jmtFast1, .lamaManga])
        #expect(!harness.folderExists(of: .v4s))

        await model.deleteAll()
        #expect(model.installedModels.isEmpty)
        #expect(model.installedBytes == 0)
        guard case .missing = model.setState else {
            Issue.record("Expected the set to be missing after deleting everything, got \(model.setState)")
            return
        }
    }

    @Test func translatedPagesAreMeasuredAndCleared() async throws {
        let harness = TranslationStoreHarness()
        let database = try await TestDatabase.inMemory()
        let writer = PageTranslationResultWriter(database: database, logger: .console())
        let patches = PageTranslationPatchStore(directory: TranslationSamples.temporaryFolder())
        defer { try? FileManager.default.removeItem(at: patches.directory) }
        let key = PageTranslationModelSet.default.key
        await writer.add(PageTranslation(
            gid: "1", pageIndex: 0, modelSetKey: key, imageWidth: 100, imageHeight: 140, regions: [], createdAt: .now
        ))
        await writer.waitUntilWritten()
        let variant = PageTranslationPatchVariant(modelSet: .default, repaint: .default, renderVersion: 1)
        let patch = try await patches.prepareToWrite(gid: "1", pageIndex: 0, variant: variant)
        try Data(count: 40_000).write(to: patch)
        await patches.didWrite(patch)
        let model = harness.makeModel(cache: (writer, patches))
        #expect(model.translatedPagesBytes == nil)

        await model.load()
        #expect((model.translatedPagesBytes ?? 0) >= 40_000)

        await model.clearTranslatedPages()
        #expect(model.translatedPagesBytes == 0)
        #expect(!model.isClearingTranslatedPages)
        #expect(!FileManager.default.fileExists(atPath: patch.path(percentEncoded: false)))
        #expect(try await writer.translatedPageCount(gid: "1", modelSetKey: key) == 0)
    }

    // MARK: The private model source

    @Test func theAddressIsValidatedAndWrittenWhenCommitted() async {
        let harness = TranslationStoreHarness(privateStore: false)
        let model = harness.makeModel()
        #expect(model.addressState == .empty)

        let cases: [(String, PageTranslationSettingsModel.AddressState)] = [
            ("  ", .empty),
            ("https://models.example/store", .valid),
            ("https://models.example/store/", .valid),
            ("http://localhost:8080/models", .valid),
            ("http://models.example/store", .invalid),
            ("ftp://models.example", .invalid),
            ("models.example", .invalid),
            ("https://user@models.example", .invalid)
        ]
        for (text, state) in cases {
            model.addressDraft = text
            #expect(model.addressState == state, "\(text)")
        }
        #expect(harness.settings.pageTranslationSourceAddress == "")

        model.addressDraft = "https://models.example/store"
        model.commitAddress()
        #expect(harness.settings.pageTranslationSourceAddress == "https://models.example/store")
        #expect(harness.store.privateStoreAddress?.absoluteString == "https://models.example/store")
        // The private-only detector can be chosen now.
        #expect(model.canChoose(.detector(.k2xl)))
    }

    @Test func theTokenIsKeptAndRemovedAndNeverReadBack() async {
        let harness = TranslationStoreHarness(privateStore: false)
        let model = harness.makeModel()
        await model.load()
        #expect(!model.hasToken)

        await model.saveToken("   ")
        #expect(!model.hasToken)
        await model.saveToken("  made-up-token\n")
        #expect(model.hasToken)
        #expect(harness.tokens.read() == "made-up-token")

        await model.removeToken()
        #expect(!model.hasToken)
        #expect(harness.tokens.read() == nil)
    }

    @Test func theAddressShownIsTheOneInTheSettings() {
        let harness = TranslationStoreHarness()
        let model = harness.makeModel()
        #expect(model.addressDraft == TranslationSamples.privateStore.absoluteString)
        #expect(model.addressState == .valid)
    }

    // MARK: Models and licences

    @Test func everyArtifactHasItsCredits() async throws {
        let harness = TranslationStoreHarness()
        let model = harness.makeModel()
        await model.load()

        let credits = model.credits
        #expect(credits.map(\.id) == TranslationSamples.catalog.artifacts.map(\.id))
        #expect(credits.map(\.credit) == TranslationSamples.catalog.artifacts.map(\.credit))
        #expect(credits.first { $0.id == .cpt2 }?.credit.nonCommercial == true)
        #expect(credits.first { $0.id == .jmtFast1 }?.choice == .translator(.jmtFast1))
        #expect(credits.allSatisfy { !$0.hasLicenceFile })

        try harness.copyIn([.v4s])
        await model.load()
        await waitFor("the detector is installed") { harness.store.state(of: .v4s) == .installed }
        #expect(model.credits.filter(\.hasLicenceFile).map(\.id) == [.v4s])

        await model.showLicence(of: .v4s)
        #expect(model.licence == LicenceText(id: .v4s, name: "Detector C", text: "Apache License 2.0"))
        // A model that is not installed has no file to show.
        model.licence = nil
        await model.showLicence(of: .k2xl)
        #expect(model.licence == nil)
    }

    @Test func theNoticesAreLlamaCppsItsPartsAndTheFonts() async {
        let model = TranslationStoreHarness().makeModel()
        #expect(model.notices.isEmpty)

        await model.loadNotices()

        #expect(model.notices.first == .llama)
        let parts = Array(model.notices.dropFirst().prefix(PageTranslationNotice.llamaParts.count))
        #expect(parts == PageTranslationNotice.llamaParts)
        let fonts = model.notices.dropFirst(1 + parts.count)
        #expect(fonts.map(\.name) == ["Noto Sans SC", "Noto Serif SC", "EhShoko Kai"])
        for font in fonts {
            #expect(font.copyright?.hasPrefix("Copyright") == true)
            #expect(font.text.contains("SIL OPEN FONT LICENSE Version 1.1"))
        }
    }

    @Test func childRoutesAreEqualForTheSameModelAndDestination() {
        let harness = TranslationStoreHarness()
        let model = harness.makeModel()
        let other = harness.makeModel()
        let route = PageTranslationChildRoute(parent: model, destination: .choices(.translator))
        #expect(route == PageTranslationChildRoute(parent: model, destination: .choices(.translator)))
        #expect(route != PageTranslationChildRoute(parent: other, destination: .choices(.translator)))
        #expect(route != PageTranslationChildRoute(parent: model, destination: .licences))
        #expect(Route.settings(.pageTranslationChild(route)) != .settings(.pageTranslation))
        #expect(!Route.settings(.pageTranslation).hidesBrowseChrome)
    }
}
