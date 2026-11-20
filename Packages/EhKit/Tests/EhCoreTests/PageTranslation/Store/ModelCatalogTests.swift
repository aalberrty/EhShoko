import EhModels
import Foundation
import Testing
@testable import EhCore

@Suite struct ModelCatalogTests {
    private let catalog = ModelCatalog.generated

    // MARK: The generated catalog

    @Test func everyArtifactIsNamedOnce() {
        let ids = catalog.artifacts.map(\.id)
        #expect(Set(ids).count == ids.count)
        #expect(catalog.version >= 1)
    }

    @Test func everyFileHasASizeAndAChecksum() {
        for artifact in catalog.artifacts {
            #expect(!artifact.files.isEmpty, "\(artifact.id)")
            #expect(Set(artifact.files.map(\.path)).count == artifact.files.count, "\(artifact.id) lists a file twice")
            for file in artifact.files {
                #expect(file.size > 0, "\(artifact.id)/\(file.path)")
                #expect(file.sha256.count == 64 && file.sha256.allSatisfy { $0.isHexDigit && !$0.isUppercase })
                #expect(!file.path.hasPrefix("/") && !file.path.split(separator: "/").contains(".."))
            }
        }
    }

    @Test func aPackageIsListedAsItsThreeFiles() {
        for artifact in catalog.artifacts {
            for package in artifact.packages {
                let files = artifact.files.filter { $0.package == package }.map { String($0.path.dropFirst(package.count + 1)) }
                #expect(Set(files) == [
                    "Manifest.json", "Data/com.apple.CoreML/model.mlmodel", "Data/com.apple.CoreML/weights/weight.bin"
                ], "\(artifact.id)/\(package)")
            }
            if case .coreML = artifact.loading { #expect(!artifact.packages.isEmpty, "\(artifact.id)") }
        }
    }

    /// The licence's text and the credits travel with every artifact a store of ours holds.
    @Test func whatAStoreHoldsCarriesItsLicenceAndCredits() {
        for artifact in catalog.artifacts where artifact.sharing != .fromPublisher {
            #expect(artifact.licenceFile != nil, "\(artifact.id)")
            #expect(artifact.creditsFile != nil, "\(artifact.id)")
            #expect(artifact.publisherAddresses.isEmpty)
        }
    }

    @Test func whatItsAuthorHostsNamesWhere() {
        for artifact in catalog.artifacts where artifact.sharing == .fromPublisher {
            #expect(!artifact.publisherAddresses.isEmpty, "\(artifact.id)")
            #expect(artifact.publisherAddresses.allSatisfy { $0.scheme == "https" && $0.host() != nil })
        }
    }

    @Test func everyArtifactHasItsCredit() {
        for artifact in catalog.artifacts {
            let credit = artifact.credit
            #expect(!credit.name.isEmpty && !credit.author.isEmpty && !credit.licence.isEmpty, "\(artifact.id)")
            #expect(credit.source.scheme == "https" && credit.licenceText.scheme == "https")
            // What its author hosts is passed on unchanged and says nothing of changes.
            if artifact.sharing == .fromPublisher { #expect(credit.changes == nil, "\(artifact.id)") }
            // A licence that forbids commercial use is named as one.
            if credit.nonCommercial { #expect(credit.licence.contains("NC"), "\(artifact.id)") }
        }
    }

    @Test func theChoicesOfTheSettingsAreInTheCatalog() {
        for detector in TextDetectorChoice.allCases { #expect(catalog.artifact(detector.artifact)?.role == .detector) }
        for reader in TextReaderChoice.allCases { #expect(catalog.artifact(reader.artifact)?.role == .reader) }
        #expect(catalog.artifact(TranslatorChoice.default.artifact)?.role == .translator)
        for repaint in RepaintChoice.allCases {
            guard let artifact = repaint.artifact else { continue }
            #expect(catalog.artifact(artifact)?.role == .repaint)
        }
    }

    /// The default detector comes first, and the one everyone may have before the last.
    @Test func detectorsFallBackInTheCatalogsOrder() {
        let detectors = catalog.artifacts(for: .detector).map(\.id)
        #expect(detectors.first == TextDetectorChoice.default.artifact)
        let shareable = catalog.artifacts(for: .detector).filter { $0.sharing == .publicStore }.map(\.id)
        #expect(shareable.first == .v4s)
    }

    /// Detector, reader, translator and the repaint model: about 1,175 MB.
    @Test func theDefaultSetIsWhatThePlanSays() {
        let ids = PageTranslationModelSet.default.artifacts + [RepaintChoice.default.artifact].compactMap { $0 }
        let bytes = ids.reduce(Int64(0)) { $0 + (catalog.artifact($1)?.downloadSize ?? 0) }
        #expect((1_170_000_000...1_180_000_000).contains(bytes), "\(bytes)")
    }

    /// The models the project converted itself say what was changed. A licence's own
    /// "non-commercial" is kept apart from a card that states no licence at all.
    @Test func theConvertedModelsSayWhatWasChanged() throws {
        for id in [ModelArtifactID.k2xl, .yolo26s, .v4s, .rtmdet2, .cpt2, .lamaManga, .bigLama] {
            let credit = try #require(catalog.artifact(id)).credit
            #expect(credit.changes?.contains("Core ML") == true, "\(id)")
        }
        #expect(catalog.artifact(.cpt2)?.credit.nonCommercial == true)
        #expect(catalog.artifact(.jmtFast1)?.credit.nonCommercial == true)
        #expect(catalog.artifact(.k2xl)?.credit.nonCommercial == false)
        #expect(catalog.artifact(.k2xl)?.credit.licence.contains("no licence stated") == true)
        #expect(catalog.artifact(.v4s)?.credit.licence == "Apache-2.0")
    }

    @Test func thePublicStoreHasNoAddressYet() {
        #expect(ModelCatalog.publicStoreAddress == nil)
        #expect(ModelSourceConfiguration().publicStore == nil)
    }

    // MARK: The types

    @Test func aFileKnowsItsPackage() {
        #expect(ModelFile("A.mlpackage/Manifest.json", 1, "").package == "A.mlpackage")
        #expect(ModelFile("coreml/B.mlpackage/Data/com.apple.CoreML/weights/weight.bin", 1, "").package == "coreml/B.mlpackage")
        #expect(ModelFile("vocab.txt", 1, "").package == nil)
        #expect(ModelFile("model.gguf", 1, "").package == nil)
        // A file that only looks like a package is a file.
        #expect(ModelFile("odd.mlpackage", 1, "").package == nil)
        #expect(ModelStoreLayout.compiledPath(ofPackage: "coreml/B.mlpackage") == "coreml/B.mlmodelc")
    }

    @Test func aLanguageModelIsOneFileWithNoPackage() {
        let artifact = StoreSamples.artifact(.galTransl4B)
        #expect(artifact.packages.isEmpty)
        #expect(artifact.loading == .languageModel(promptFamily: "galtransl"))
        #expect(artifact.downloadSize == 10_500 + 400 + 120)
    }

    /// The catalog decodes from the JSON the script prints with `--json`.
    @Test func theCatalogDecodesFromTheScriptsJSON() throws {
        let json = """
        {
          "version": 3,
          "artifacts": [
            {
              "id": "det-v4s", "version": "2", "role": "detector", "sharing": "publicStore",
              "credit": {
                "name": "A detector", "author": "Someone", "source": "https://example.com/model",
                "licence": "Apache-2.0", "licenceText": "https://example.com/licence",
                "changes": "Converted to Core ML.", "nonCommercial": false
              },
              "loading": { "coreML": { "_0": "cpuOnly" } },
              "publisherAddresses": [],
              "files": [ { "path": "V4S.mlpackage/Manifest.json", "size": 617, "sha256": "3a6b" } ]
            },
            {
              "id": "mt-hy-mt2-1.8b", "version": "1", "role": "translator", "sharing": "fromPublisher",
              "credit": {
                "name": "A translator", "author": "Someone", "source": "https://example.com/llm",
                "licence": "Apache-2.0", "licenceText": "https://example.com/licence", "nonCommercial": false
              },
              "loading": { "languageModel": { "promptFamily": "hymt2" } },
              "publisherAddresses": ["https://example.com/llm/resolve/abc"],
              "files": [ { "path": "model.gguf", "size": 1133080448, "sha256": "dc5f" } ]
            }
          ]
        }
        """
        let decoded = try JSONDecoder().decode(ModelCatalog.self, from: Data(json.utf8))
        #expect(decoded.version == 3)
        #expect(decoded.artifacts.map(\.id) == [.v4s, .hyMT2])
        let detector = try #require(decoded.artifact(.v4s))
        #expect(detector.loading == .coreML(.cpuOnly))
        #expect(detector.sharing == .publicStore)
        #expect(detector.files == [ModelFile("V4S.mlpackage/Manifest.json", 617, "3a6b")])
        #expect(detector.credit.changes == "Converted to Core ML.")
        let translator = try #require(decoded.artifact(.hyMT2))
        #expect(translator.loading == .languageModel(promptFamily: "hymt2"))
        #expect(translator.credit.changes == nil)
        #expect(translator.publisherAddresses == [URL(string: "https://example.com/llm/resolve/abc")!])
        #expect(translator.downloadSize == 1_133_080_448)
    }

    @Test func theCatalogSurvivesCoding() throws {
        let data = try JSONEncoder().encode(catalog)
        #expect(try JSONDecoder().decode(ModelCatalog.self, from: data) == catalog)
    }
}

@Suite struct ModelSourcesTests {
    private let privateStore = StoreSamples.privateStore
    private let publicStore = StoreSamples.publicStore

    private func kinds(_ id: ModelArtifactID, _ configuration: ModelSourceConfiguration) -> [ModelFileSource.Kind] {
        let artifact = StoreSamples.artifact(id)
        return configuration.sources(for: artifact.files[0], of: artifact).map(\.kind)
    }

    // MARK: The order of sources

    /// Publisher, private store, public store; each left out when it does not apply.
    @Test func theOwnerWithAPrivateStore() {
        let configuration = ModelSourceConfiguration(privateStore: privateStore, token: "t", publicStore: nil)
        #expect(kinds(.jmtFast1, configuration) == [.publisher, .publisher, .privateStore])
        #expect(kinds(.cpt2, configuration) == [.privateStore])
        #expect(kinds(.k2xl, configuration) == [.privateStore])
    }

    @Test func everyoneElseOnceThereIsAPublicStore() {
        let configuration = ModelSourceConfiguration(privateStore: nil, token: nil, publicStore: publicStore)
        #expect(kinds(.jmtFast1, configuration) == [.publisher, .publisher])
        #expect(kinds(.cpt2, configuration) == [.publicStore])
        #expect(kinds(.k2xl, configuration).isEmpty)
    }

    @Test func someoneWithTheirOwnStoreBesideThePublicOne() {
        let configuration = ModelSourceConfiguration(privateStore: privateStore, token: nil, publicStore: publicStore)
        #expect(kinds(.jmtFast1, configuration) == [.publisher, .publisher, .privateStore])
        #expect(kinds(.cpt2, configuration) == [.privateStore, .publicStore])
        #expect(kinds(.k2xl, configuration) == [.privateStore])
    }

    @Test func withoutAnyStoreOnlyAuthorsAreAsked() {
        let configuration = ModelSourceConfiguration(privateStore: nil, token: nil, publicStore: nil)
        #expect(kinds(.jmtFast1, configuration) == [.publisher, .publisher])
        #expect(kinds(.cpt2, configuration).isEmpty)
        #expect(kinds(.k2xl, configuration).isEmpty)
        #expect(configuration.offers(StoreSamples.artifact(.jmtFast1)))
        #expect(!configuration.offers(StoreSamples.artifact(.cpt2)))
        #expect(!configuration.offers(StoreSamples.artifact(.k2xl)))
    }

    @Test func whatASourceOffersFollowsTheSharingKind() {
        let withPublic = ModelSourceConfiguration(privateStore: nil, token: nil, publicStore: publicStore)
        #expect(withPublic.offers(StoreSamples.artifact(.cpt2)))
        #expect(!withPublic.offers(StoreSamples.artifact(.k2xl)))
        let withPrivate = ModelSourceConfiguration(privateStore: privateStore, token: nil, publicStore: nil)
        #expect(withPrivate.offers(StoreSamples.artifact(.cpt2)))
        #expect(withPrivate.offers(StoreSamples.artifact(.k2xl)))
    }

    // MARK: Addresses and the token

    @Test func aFilesAddressIsStoreArtifactVersionPath() {
        let artifact = StoreSamples.artifact(.v4s)
        let file = artifact.files[2]
        let configuration = ModelSourceConfiguration(privateStore: privateStore, token: "t", publicStore: publicStore)
        let sources = configuration.sources(for: file, of: artifact)
        #expect(sources.map(\.url.absoluteString) == [
            "https://private.example/models/det-v4s/2/V4S.mlpackage/Data/com.apple.CoreML/weights/weight.bin",
            "https://public.example/models/det-v4s/2/V4S.mlpackage/Data/com.apple.CoreML/weights/weight.bin"
        ])
        let translator = StoreSamples.artifact(.jmtFast1)
        #expect(configuration.sources(for: translator.files[3], of: translator).map(\.url.absoluteString) == [
            "https://author.example/model/resolve/abc123/coreml/host/table.npy",
            "https://mirror.example/model/resolve/master/coreml/host/table.npy",
            "https://private.example/models/mt-jmt-fast-1/1/coreml/host/table.npy"
        ])
    }

    /// The token is the private store's and goes with no other source.
    @Test func onlyThePrivateStoreGetsTheToken() {
        let configuration = ModelSourceConfiguration(privateStore: privateStore, token: "secret", publicStore: publicStore)
        for artifact in StoreSamples.catalog.artifacts {
            for source in configuration.sources(for: artifact.files[0], of: artifact) {
                #expect(source.token == (source.kind == .privateStore ? "secret" : nil), "\(artifact.id) \(source.kind)")
                if source.token != nil { #expect(source.url.host() == privateStore.host()) }
            }
        }
    }

    @Test(arguments: [
        ("https://huggingface.co/someone/models/resolve/main", "https://huggingface.co/someone/models/resolve/main"),
        ("  https://example.com/store/ \n", "https://example.com/store"),
        ("https://example.com", "https://example.com"),
        ("http://127.0.0.1:8080/store", "http://127.0.0.1:8080/store"),
        ("http://localhost:8080", "http://localhost:8080")
    ])
    func anAddressThatCanBeAStore(text: String, expected: String) {
        #expect(ModelSourceConfiguration.address(from: text)?.absoluteString == expected)
    }

    /// Plain http would carry the token unencrypted; it is taken for this device only.
    @Test(arguments: [
        "", "   ", "not an address", "example.com/store", "ftp://example.com/store", "http://example.com/store",
        "https://", "https://user:password@example.com/store", "https://example.com/store?token=1",
        "file:///tmp/store"
    ])
    func textThatCannotBeAStore(text: String) {
        #expect(ModelSourceConfiguration.address(from: text) == nil)
    }
}
